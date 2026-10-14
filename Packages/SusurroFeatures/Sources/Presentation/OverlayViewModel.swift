import DesignSystem
import Domain
import Observation
import SusurroUI

/// Turns the pipeline's states into the state of the overlay. A state that dismisses itself (inserted, a notice, an
/// error) is held for its dwell even though the pipeline moves on at once, and the states that arrive meanwhile wait for
/// it, the latest of them first in line. A new recording, an error, and a busy notice cannot wait and replace it. A busy
/// notice is the exception among the held states: it only says that the last dictation is still under way, so the result
/// of that dictation replaces it at once.
///
/// While the pipeline is idle, the progress of the speech model load shows, if there is any, and so does the warning
/// that the model could not load.
///
/// The input level reaches the meter no more often than 30 times a second. The style of the overlay and its edge follow
/// the settings.
@MainActor
@Observable
public final class OverlayViewModel: OverlayViewModeling {
    /// What is on screen now.
    public private(set) var state = OverlayViewState.hidden
    public private(set) var level = 0.0
    public private(set) var styleID = OverlaySettings.variant.defaultValue
    /// The edge the user chose, or nil to follow the theme's.
    public private(set) var edgePreference: ScreenEdge?

    /// Shows the state: the window of the overlay is behind this, or a recorder in a test. It is called each time the
    /// state changes.
    @ObservationIgnored public var display: @MainActor (OverlayViewState) -> Void = { _ in }

    @ObservationIgnored private let timing: OverlayTiming
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var throttle: LevelThrottle
    @ObservationIgnored private var modelProgress: Double?
    @ObservationIgnored private var holding: Task<Void, Never>?
    /// The latest state that arrived while a state was held.
    @ObservationIgnored private var waiting: PipelineState?
    /// Whether the state that is held is the busy notice.
    @ObservationIgnored private var isHoldingBusyNotice = false
    @ObservationIgnored private var isPipelineActive = false

    /// - Parameters:
    ///   - sleep: Times the dwell of a state. Tests pass a fake.
    ///   - uptime: The time since an arbitrary origin, which spaces the levels.
    public convenience init(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        uptime: @escaping () -> Duration = OverlayViewModel.continuousUptime()
    ) {
        self.init(timing: .standard, sleep: sleep, uptime: uptime)
    }

    init(
        timing: OverlayTiming = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        uptime: @escaping () -> Duration = OverlayViewModel.continuousUptime()
    ) {
        self.timing = timing
        self.sleep = sleep
        throttle = LevelThrottle(uptime: uptime)
    }

    /// The time since the first call of the function it returns, on the continuous clock.
    public nonisolated static func continuousUptime() -> () -> Duration {
        let origin = ContinuousClock.now
        return { origin.duration(to: .now) }
    }

    /// The time since now on `clock`, for a graph that paces everything with one clock.
    public static func uptime(of clock: any Clock<Duration>) -> () -> Duration {
        func uptime<C: Clock<Duration>>(_ clock: C) -> () -> Duration {
            let origin = clock.now
            return { origin.duration(to: clock.now) }
        }
        return uptime(clock)
    }

    // MARK: The pipeline

    /// Shows the state of each pipeline state, until the stream ends.
    public func run(states: AsyncStream<PipelineState>) async {
        for await state in states { apply(state) }
    }

    /// Shows the input level of each chunk, until the stream ends.
    public func run(levels: AsyncStream<Double>) async {
        for await level in levels { setLevel(level) }
    }

    func apply(_ pipeline: PipelineState) {
        if holding != nil, !replacesAHeldState(pipeline) {
            wait(pipeline)
            return
        }
        show(pipeline)
    }

    /// An input level, from 0 to 1. Levels that come in faster than the meter can use are dropped.
    func setLevel(_ new: Double) {
        guard case .recording = state, let delivered = throttle.accept(new) else { return }
        level = delivered
    }

    // MARK: The model

    /// The progress of the speech model load, or nil when it is not loading. It shows when nothing else does.
    public func setModelProgress(_ progress: Double?) {
        modelProgress = progress
        if holding == nil, !isPipelineActive { update(modelState()) }
    }

    /// Tells that the speech model could not load. The warning holds for the error dwell, in place of the progress. It
    /// does not cover a dictation or a state that is held, and it is not shown later.
    public func showModelUnavailable() {
        modelProgress = nil
        guard holding == nil, !isPipelineActive else { return }
        update(OverlayMapping.modelUnavailable)
        hold(for: timing.error)
    }

    // MARK: The settings

    /// Follows the overlay's settings until the store goes away: the id of the style, and the edge.
    public func follow(_ settings: any SettingsStore) async {
        let changes = settings.changes()
        read(settings)
        for await change in changes where change.name.hasPrefix("overlay.") { read(settings) }
    }

    func read(_ settings: any SettingsStore) {
        styleID = settings.value(for: OverlaySettings.variant)
        edgePreference =
            switch settings.value(for: OverlaySettings.edge) {
            case .followTheme: nil
            case .top: .top
            case .bottom: .bottom
            }
    }

    // MARK: Showing

    /// A recording that starts, an error, and a press that was refused matter more than whatever is held. So does the
    /// result of a dictation when what is held is only the notice that it is still under way.
    private func replacesAHeldState(_ pipeline: PipelineState) -> Bool {
        switch pipeline {
        case .starting, .recording, .error, .notice(.busy): true
        case .inserted, .notice: isHoldingBusyNotice
        case .idle, .transcribing: false
        }
    }

    /// Keeps `pipeline` for when the held state is done. The latest state is the one that counts, except that a result
    /// that is waiting is not replaced by the idle state or the progress that follow it.
    private func wait(_ pipeline: PipelineState) {
        if let waiting, timing.dwell(for: waiting) != nil, timing.dwell(for: pipeline) == nil { return }
        waiting = pipeline
    }

    private func show(_ pipeline: PipelineState) {
        holding?.cancel()
        holding = nil
        waiting = nil
        isHoldingBusyNotice = pipeline == .notice(.busy)
        isPipelineActive = pipeline != .idle
        let mapped = OverlayMapping.viewState(for: pipeline)
        update(mapped.isHidden ? modelState() : mapped)
        if let dwell = timing.dwell(for: pipeline) { hold(for: dwell) }
    }

    private func hold(for dwell: Duration) {
        holding = Task { [sleep] in
            do { try await sleep(dwell) } catch { return }
            // Another state may have replaced this one while the task was resuming.
            guard !Task.isCancelled else { return }
            holdEnded()
        }
    }

    private func holdEnded() {
        holding = nil
        let next = waiting ?? .idle
        waiting = nil
        show(next)
    }

    private func modelState() -> OverlayViewState {
        modelProgress.map { OverlayMapping.modelLoading(progress: $0) } ?? .hidden
    }

    private func update(_ new: OverlayViewState) {
        guard new != state else { return }
        if case .recording = new {
        } else {
            level = 0
            throttle.reset()
        }
        state = new
        display(new)
    }
}
