import Domain

/// What the overlay shows for a pipeline state: a symbol, a message, and optionally how far a load has got. It is a pure
/// function of the state, so it is tested without a window. The message names the way out of an error, since the
/// overlay cannot be clicked.
public struct OverlayIndicator: Equatable, Sendable {
    /// How the indicator is colored. The view turns it into system colors; the unthemed skeleton has no palette.
    public enum Tone: Equatable, Sendable {
        case neutral
        case recording
        case success
        case warning
        case error
    }

    public let tone: Tone
    /// An SF Symbol name.
    public let symbol: String
    public let message: String
    /// A fraction between 0 and 1 when the indicator shows a bar.
    public let progress: Double?

    /// Nil for an idle pipeline, which shows nothing.
    static func indicator(for state: PipelineState) -> OverlayIndicator? {
        switch state {
        case .idle:
            nil
        case .starting:
            OverlayIndicator(tone: .neutral, symbol: "mic", message: "Getting ready…", progress: nil)
        case .recording:
            OverlayIndicator(tone: .recording, symbol: "mic.fill", message: "Listening…", progress: nil)
        case .transcribing(let progress?):
            modelLoading(progress: progress)
        case .transcribing(nil):
            OverlayIndicator(tone: .neutral, symbol: "waveform", message: "Transcribing…", progress: nil)
        case .inserted:
            OverlayIndicator(tone: .success, symbol: "checkmark.circle.fill", message: "Pasted", progress: nil)
        case .notice(let kind):
            notice(kind)
        case .error(let error):
            OverlayIndicator(
                tone: .error, symbol: "exclamationmark.triangle.fill", message: message(for: error), progress: nil)
        }
    }

    /// The speech model failed to load after its progress had been on screen.
    static let modelUnavailable = OverlayIndicator(
        tone: .warning, symbol: "exclamationmark.triangle",
        message: "Speech model unavailable. Open the Susurro menu for details.", progress: nil)

    /// The speech model loading, whether a dictation waits for it or the app is idle.
    static func modelLoading(progress: Double) -> OverlayIndicator {
        let fraction = progress.loadFraction
        return OverlayIndicator(
            tone: .neutral, symbol: "arrow.down.circle",
            message: "Preparing the speech model… \(Int((fraction * 100).rounded()))%", progress: fraction)
    }

    private static func notice(_ kind: NoticeKind) -> OverlayIndicator {
        let (symbol, message): (String, String) =
            switch kind {
            case .noSpeech:
                ("mic.slash", "No speech heard")
            case .capReached:
                ("clock", "Recording limit reached. Transcribing what was said…")
            case .copiedToClipboard(.accessibilityMissing):
                (
                    "doc.on.clipboard",
                    "Copied to the clipboard. Turn on Accessibility in the Susurro menu to paste automatically."
                )
            case .copiedToClipboard(.pasteFailed):
                ("doc.on.clipboard", "Copied to the clipboard. Paste it with Command-V.")
            case .busy:
                ("hourglass", "Still working on the last dictation")
            }
        return OverlayIndicator(tone: .warning, symbol: symbol, message: message, progress: nil)
    }

    /// What failed, then the way out. The reason the system gave is left out: it can quote what was said.
    private static func message(for error: PipelineError) -> String {
        let headline =
            switch error {
            case .microphoneNotGranted: "Microphone access is off."
            case .recognizerNotInstalled: "The speech model is missing."
            case .cloudKeyMissing: "The speech service has no API key."
            case .recognizerUnavailable: "The speech model could not load."
            case .captureFailed: "Could not record."
            case .recognitionFailed: "Transcription failed."
            case .timedOut(.readiness): "The speech model is taking too long to load."
            case .timedOut(.capture): "The microphone did not stop in time."
            case .timedOut(.transcription): "Transcription took too long."
            case .timedOut(.insertion): "Pasting took too long."
            case .notInserted(.clipboardChanged): "Not pasted: the clipboard changed meanwhile."
            case .notInserted(.clipboardWriteFailed): "The text could not be pasted or copied."
            }
        let wayOut =
            switch error.remedy {
            case .permissions: "Open the Susurro menu to turn it on."
            case .settings: "Open the Susurro menu."
            case .retry: "Hold the key to try again."
            case .addKey: "Open the Susurro menu to add a key."
            }
        return "\(headline) \(wayOut)"
    }
}
