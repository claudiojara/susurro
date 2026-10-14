import Domain
import SusurroUI

/// What the overlay shows for a pipeline state: a pure function of the state, so it is tested without a window. Every
/// text of the overlay is here. An error names the way out, since the overlay cannot be clicked.
enum OverlayMapping {
    /// How a hands-free recording is stopped, since its key is not held.
    static let handsFreeHint = "Press the shortcut again to stop. Esc cancels."

    /// The state of the overlay for a pipeline state. An idle pipeline shows nothing.
    ///
    /// There is no case for a polishing pipeline yet: the overlay can draw one (`OverlayViewState.polishing`), and the
    /// case is added here with the stage that publishes it.
    static func viewState(for state: PipelineState) -> OverlayViewState {
        switch state {
        case .idle:
            .hidden
        case .starting:
            .starting(text: "Getting ready…")
        case .recording(let mode):
            .recording(
                handsFree: mode == .handsFree, text: "Listening…", hint: mode == .handsFree ? handsFreeHint : nil)
        case .transcribing(let progress?):
            modelLoading(progress: progress)
        case .transcribing(nil):
            .transcribing(text: "Transcribing…", progress: nil)
        case .inserted:
            .inserted(text: "Pasted")
        case .notice(let kind):
            notice(kind)
        case .error(let error):
            .error(text: message(for: error))
        }
    }

    /// The speech model failed to load after its progress had been on screen.
    static let modelUnavailable = OverlayViewState.notice(
        symbol: "exclamationmark.triangle", text: "Speech model unavailable. Open the Susurro menu for details.")

    /// The speech model loading, whether a dictation waits for it or the app is idle.
    static func modelLoading(progress: Double) -> OverlayViewState {
        let fraction = progress.loadFraction
        return .transcribing(
            text: "Preparing the speech model… \(Int((fraction * 100).rounded()))%", progress: fraction)
    }

    private static func notice(_ kind: NoticeKind) -> OverlayViewState {
        let (symbol, text): (String, String) =
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
        return .notice(symbol: symbol, text: text)
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
            case .timedOut(.insertion): "Pasting took too long. The text may already be there."
            case .notInserted(.clipboardChanged): "Not pasted: the clipboard changed meanwhile."
            case .notInserted(.clipboardWriteFailed): "The text could not be pasted or copied."
            }
        let wayOut =
            switch error.remedy {
            case .permissions: "Open the Susurro menu to turn it on."
            case .settings: "Open the Susurro menu."
            case .retry: "Hold the key to try again."
            case .check: "Check the app before you dictate again."
            case .addKey: "Open the Susurro menu to add a key."
            }
        return "\(headline) \(wayOut)"
    }
}
