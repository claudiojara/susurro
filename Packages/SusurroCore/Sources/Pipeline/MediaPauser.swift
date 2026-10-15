import Activation
import Domain

/// Pauses the media players that play while the user dictates, and plays them again after, when the user turned it on
/// (`MediaSettings.pauseWhileDictating`). It follows the pipeline's states: a recording starts with `starting` or
/// `recording`, and any other state ends it. Each player is asked for its own state and sent its own pause and play
/// commands, never the play/pause key: a player that does not play, is not open, or cannot be asked gets nothing, and
/// only the players it paused are played again. See ADR 0038, which replaces the media key of ADR 0031.
///
/// The players are asked only once a recording has lasted `delay` (the hold threshold): every press publishes
/// `starting`, and a tap ends before that, so a tap or the first press of a double tap touches no player at all.
public actor MediaPauser {
    private let players: [any MediaPlayerControlling]
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
    /// The players this recording paused, by index in `players`: exactly these are played again as it ends.
    private var pausedByUs: [Int] = []

    public init(
        players: [any MediaPlayerControlling], settings: any SettingsStore,
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        delay: Duration = ActivationMachine.Timing.standard.holdThreshold,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.players = players
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
            let paused = pausedByUs
            pausedByUs = []
            guard !paused.isEmpty else { return }
            for index in paused { await players[index].play() }
            diagnostics.record(.mediaPlayback(paused: false))
        }
    }

    /// Waits until the pause that is due, if any, has been sent or dropped.
    public func settle() async {
        await pendingPause?.value
    }

    private func pauseAfterDelay(of current: Int) async {
        guard (try? await sleep(delay)) != nil, isStill(current) else { return }
        guard settings.value(for: MediaSettings.pauseWhileDictating) else { return }
        var pausedAny = false
        for (index, player) in players.enumerated() {
            guard await player.state() == .playing, isStill(current) else { continue }
            // Marked before the pause is sent: a recording that ends while it is on its way plays it again.
            pausedByUs.append(index)
            pausedAny = true
            await player.pause()
        }
        if pausedAny { diagnostics.record(.mediaPlayback(paused: true)) }
    }

    private func isStill(_ current: Int) -> Bool {
        isRecording && recording == current && !Task.isCancelled
    }
}
