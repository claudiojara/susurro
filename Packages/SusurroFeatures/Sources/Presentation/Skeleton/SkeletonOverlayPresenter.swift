import Domain

/// Turns the pipeline's states into the indicator on screen. An indicator that dismisses itself (inserted, a notice, an
/// error) is held for its dwell even though the pipeline moves on at once, and the states that arrive meanwhile wait for
/// it, the latest of them first in line. A new recording, an error, and a busy notice cannot wait and replace it. A busy
/// notice is the exception among the held indicators: it only says that the last dictation is still under way, so the
/// result of that dictation replaces it at once.
///
/// While the pipeline is idle, the progress of the speech model load shows, if there is any, and so does the warning
/// that the model could not load.
@MainActor
public final class SkeletonOverlayPresenter {
    private let timing: OverlayTiming
    private let sleep: @Sendable (Duration) async throws -> Void
    private let display: @MainActor (OverlayIndicator?) -> Void
    private var modelProgress: Double?
    private var holding: Task<Void, Never>?
    /// The latest state that arrived while an indicator was held.
    private var waiting: PipelineState?
    /// Whether the indicator that is held is the busy notice.
    private var isHoldingBusyNotice = false

    /// What is on screen now.
    public private(set) var indicator: OverlayIndicator?

    /// - Parameters:
    ///   - sleep: Times the dwell of an indicator. Tests pass a fake.
    ///   - display: Shows the indicator, or hides the overlay when it is nil.
    public convenience init(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        display: @escaping @MainActor (OverlayIndicator?) -> Void
    ) {
        self.init(timing: .standard, sleep: sleep, display: display)
    }

    init(
        timing: OverlayTiming = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        display: @escaping @MainActor (OverlayIndicator?) -> Void
    ) {
        self.timing = timing
        self.sleep = sleep
        self.display = display
    }

    /// Shows the indicator of each state the pipeline publishes, until the stream ends.
    public func run(states: AsyncStream<PipelineState>) async {
        for await state in states { apply(state) }
    }

    func apply(_ state: PipelineState) {
        if holding != nil, !replacesAHeldIndicator(state) {
            wait(state)
            return
        }
        show(state)
    }

    /// The progress of the speech model load, or nil when it is not loading. It shows when nothing else does.
    public func setModelProgress(_ progress: Double?) {
        modelProgress = progress
        if holding == nil, !isPipelineActive { update(modelIndicator()) }
    }

    /// Tells that the speech model could not load. The warning holds for the error dwell, in place of the progress. It
    /// does not cover a dictation or an indicator that is held, and it is not shown later.
    public func showModelUnavailable() {
        modelProgress = nil
        guard holding == nil, !isPipelineActive else { return }
        update(.modelUnavailable)
        hold(for: timing.error)
    }

    // MARK: Showing

    private var isPipelineActive = false

    /// A recording that starts, an error, and a press that was refused matter more than whatever is held. So does the
    /// result of a dictation when what is held is only the notice that it is still under way.
    private func replacesAHeldIndicator(_ state: PipelineState) -> Bool {
        switch state {
        case .starting, .recording, .error, .notice(.busy): true
        case .inserted, .notice: isHoldingBusyNotice
        case .idle, .transcribing, .polishing: false
        }
    }

    /// Keeps `state` for when the held indicator is done. The latest state is the one that counts, except that a result
    /// that is waiting is not replaced by the idle state or the progress that follow it.
    private func wait(_ state: PipelineState) {
        if let waiting, timing.dwell(for: waiting) != nil, timing.dwell(for: state) == nil { return }
        waiting = state
    }

    private func show(_ state: PipelineState) {
        holding?.cancel()
        holding = nil
        waiting = nil
        isHoldingBusyNotice = state == .notice(.busy)
        isPipelineActive = state != .idle
        update(OverlayIndicator.indicator(for: state) ?? modelIndicator())
        if let dwell = timing.dwell(for: state) { hold(for: dwell) }
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

    private func modelIndicator() -> OverlayIndicator? {
        modelProgress.map { OverlayIndicator.modelLoading(progress: $0) }
    }

    private func update(_ new: OverlayIndicator?) {
        guard new != indicator else { return }
        indicator = new
        display(new)
    }
}
