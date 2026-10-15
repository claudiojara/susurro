import Domain

/// Pauses the media that plays while the user dictates, and resumes it after, when the user turned it on
/// (`MediaSettings.pauseWhileDictating`). It follows the pipeline's states: a recording starts with `starting` or
/// `recording`, and any other state ends it. Only what it paused is resumed, so media the user had paused stays paused,
/// and a recording that finds nothing playing sends nothing. See ADR 0031.
public actor MediaPauser {
    private let playback: any MediaPlaybackControlling
    private let settings: any SettingsStore
    private let diagnostics: any DiagnosticsLog
    /// A recording is under way and was looked at.
    private var isRecording = false
    /// The media key was sent as the recording started, so it is sent again as it ends.
    private var pausedByUs = false

    public init(
        playback: any MediaPlaybackControlling, settings: any SettingsStore,
        diagnostics: any DiagnosticsLog = NoDiagnostics()
    ) {
        self.playback = playback
        self.settings = settings
        self.diagnostics = diagnostics
    }

    /// Takes the next state of the pipeline. The caller awaits each one, so the states are taken in order.
    public func observe(_ state: PipelineState) async {
        switch state {
        case .starting, .recording:
            guard !isRecording else { return }
            isRecording = true
            guard settings.value(for: MediaSettings.pauseWhileDictating), await playback.isPlaying() else { return }
            await playback.togglePlayPause()
            pausedByUs = true
            diagnostics.record(.mediaPlayback(paused: true))
        default:
            guard isRecording else { return }
            isRecording = false
            // What was paused is resumed even if the setting was turned off meanwhile: it was ours to pause.
            guard pausedByUs else { return }
            pausedByUs = false
            await playback.togglePlayPause()
            diagnostics.record(.mediaPlayback(paused: false))
        }
    }
}
