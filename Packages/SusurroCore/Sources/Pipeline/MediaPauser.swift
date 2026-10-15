import Activation
import Domain

/// Pauses the media that plays while the user dictates, and resumes it after, when the user turned it on
/// (`MediaSettings.pauseWhileDictating`). It follows the pipeline's states: a recording starts with `starting` or
/// `recording`, and any other state ends it. Only what it paused is resumed, so media the user had paused stays paused,
/// and a recording that finds nothing playing sends nothing. See ADR 0031.
///
/// The media is looked at only once a recording has lasted `delay` (the hold threshold): every press publishes
/// `starting`, and a tap ends before that, so a tap or the first press of a double tap sends no media key at all.
public actor MediaPauser {
    private let playback: any MediaPlaybackControlling
    private let settings: any SettingsStore
    private let diagnostics: any DiagnosticsLog
    private let delay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    /// A recording is under way.
    private var isRecording = false
    /// Counts the recordings, so a pause that was due for one that has ended is dropped.
    private var recording = 0
    /// The pause that waits for the recording to last `delay`.
    private var pendingPause: Task<Void, Never>?
    /// The media key was sent as the recording started, so it is sent again as it ends.
    private var pausedByUs = false

    public init(
        playback: any MediaPlaybackControlling, settings: any SettingsStore,
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        delay: Duration = ActivationMachine.Timing.standard.holdThreshold,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.playback = playback
        self.settings = settings
        self.diagnostics = diagnostics
        self.delay = delay
        self.sleep = sleep
    }

    /// Takes the next state of the pipeline. The caller awaits each one, so the states are taken in order.
    public func observe(_ state: PipelineState) async {
        switch state {
        case .starting, .recording:
            guard !isRecording else { return }
            isRecording = true
            recording += 1
            let current = recording
            pendingPause = Task { await self.pauseAfterDelay(of: current) }
        default:
            guard isRecording else { return }
            isRecording = false
            pendingPause?.cancel()
            // What was paused is resumed even if the setting was turned off meanwhile: it was ours to pause.
            guard pausedByUs else { return }
            pausedByUs = false
            await playback.togglePlayPause()
            diagnostics.record(.mediaPlayback(paused: false))
        }
    }

    /// Waits until the pause that is due, if any, has been sent or dropped.
    public func settle() async {
        await pendingPause?.value
    }

    private func pauseAfterDelay(of current: Int) async {
        guard (try? await sleep(delay)) != nil, isStill(current) else { return }
        guard settings.value(for: MediaSettings.pauseWhileDictating), await playback.isPlaying(), isStill(current)
        else { return }
        // Marked before the key is sent: a recording that ends while it is on its way resumes what it paused.
        pausedByUs = true
        await playback.togglePlayPause()
        diagnostics.record(.mediaPlayback(paused: true))
    }

    private func isStill(_ current: Int) -> Bool {
        isRecording && recording == current && !Task.isCancelled
    }
}
