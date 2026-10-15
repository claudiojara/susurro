import Domain
import SusurroUI

/// What the overlay shows for a pipeline state: a pure function of the state, so it is tested without a window. Every
/// text of the overlay is here. An error names the way out, since the overlay cannot be clicked.
enum OverlayMapping {
    /// How a hands-free recording is stopped, since its key is not held.
    static var handsFreeHint: String {
        L10n.string("overlay.handsFreeHint", "Press the shortcut again to stop. Esc cancels.")
    }

    /// The state of the overlay for a pipeline state. An idle pipeline shows nothing.
    static func viewState(for state: PipelineState) -> OverlayViewState {
        switch state {
        case .idle:
            .hidden
        case .starting:
            .starting(text: L10n.string("overlay.starting", "Getting ready…"))
        case .recording(let mode):
            .recording(
                handsFree: mode == .handsFree, text: L10n.string("overlay.listening", "Listening…"),
                hint: mode == .handsFree ? handsFreeHint : nil)
        case .transcribing(let progress?):
            modelLoading(progress: progress)
        case .transcribing(nil):
            .transcribing(text: L10n.string("overlay.transcribing", "Transcribing…"), progress: nil)
        case .polishing:
            .polishing(text: L10n.string("overlay.polishing", "Polishing…"))
        case .inserted:
            .inserted(text: L10n.string("overlay.inserted", "Pasted"))
        case .notice(let kind):
            notice(kind)
        case .error(let error):
            .error(text: message(for: error))
        }
    }

    /// The speech model failed to load after its progress had been on screen.
    static var modelUnavailable: OverlayViewState {
        .notice(
            symbol: "exclamationmark.triangle",
            text: L10n.string(
                "overlay.modelUnavailable", "Speech model unavailable. Open the Susurro menu for details."))
    }

    /// The speech model loading, whether a dictation waits for it or the app is idle.
    static func modelLoading(progress: Double) -> OverlayViewState {
        let fraction = progress.loadFraction
        return .transcribing(
            text: L10n.string(
                "overlay.preparingModel", "Preparing the speech model… \(Int((fraction * 100).rounded()))%"),
            progress: fraction)
    }

    private static func notice(_ kind: NoticeKind) -> OverlayViewState {
        let (symbol, text): (String, String) =
            switch kind {
            case .noSpeech:
                ("mic.slash", L10n.string("overlay.notice.noSpeech", "No speech heard"))
            case .capReached:
                (
                    "clock",
                    L10n.string("overlay.notice.capReached", "Recording limit reached. Transcribing what was said…")
                )
            case .copiedToClipboard(.accessibilityMissing):
                (
                    "doc.on.clipboard",
                    L10n.string(
                        "overlay.notice.copiedNoAccessibility",
                        "Copied to the clipboard. Turn on Accessibility in the Susurro menu to paste automatically.")
                )
            case .copiedToClipboard(.pasteFailed):
                (
                    "doc.on.clipboard",
                    L10n.string("overlay.notice.copiedPasteFailed", "Copied to the clipboard. Paste it with Command-V.")
                )
            case .deviceDisconnected:
                (
                    "mic.slash",
                    L10n.string(
                        "overlay.notice.disconnected",
                        "The microphone was disconnected. Transcribing what was recorded…")
                )
            case .silentMicrophone:
                (
                    "mic.slash",
                    L10n.string(
                        "overlay.notice.silent", "The microphone seems to be silent. Check that it is not muted.")
                )
            case .noLastDictation:
                ("text.badge.xmark", L10n.string("overlay.notice.noLastDictation", "No dictation to paste yet"))
            case .lastDictationCopied:
                (
                    "doc.on.clipboard",
                    L10n.string("overlay.notice.lastDictationCopied", "Last dictation copied to the clipboard")
                )
            }
        return .notice(symbol: symbol, text: text)
    }

    /// What failed, then the way out. The reason the system gave is left out: it can quote what was said.
    private static func message(for error: PipelineError) -> String {
        let headline =
            switch error {
            case .microphoneNotGranted: L10n.string("overlay.error.microphone", "Microphone access is off.")
            case .recognizerNotInstalled: L10n.string("overlay.error.notInstalled", "The speech model is missing.")
            case .cloudKeyMissing: L10n.string("overlay.error.cloudKey", "The speech service has no API key.")
            case .recognizerUnavailable: L10n.string("overlay.error.unavailable", "The speech model could not load.")
            case .captureFailed: L10n.string("overlay.error.capture", "Could not record.")
            case .persistenceFailed: L10n.string("overlay.error.persistence", "Could not save the recording.")
            case .providerNotUsable(.notEnabled):
                L10n.string("overlay.error.providerOff", "The selected speech provider is turned off.")
            case .providerNotUsable(.missingKey):
                L10n.string("overlay.error.providerKey", "The selected speech provider needs a key.")
            case .recognitionFailed: L10n.string("overlay.error.recognition", "Transcription failed.")
            case .timedOut(.readiness):
                L10n.string("overlay.error.timedOut.readiness", "The speech model is taking too long to load.")
            case .timedOut(.capture):
                L10n.string("overlay.error.timedOut.capture", "The microphone did not stop in time.")
            case .timedOut(.transcription):
                L10n.string("overlay.error.timedOut.transcription", "Transcription took too long.")
            case .timedOut(.cleanup): L10n.string("overlay.error.timedOut.cleanup", "Cleanup took too long.")
            case .timedOut(.insertion):
                L10n.string("overlay.error.timedOut.insertion", "Pasting took too long. The text may already be there.")
            case .notInserted(.clipboardChanged):
                L10n.string("overlay.error.clipboardChanged", "Not pasted: the clipboard changed meanwhile.")
            case .notInserted(.clipboardWriteFailed):
                L10n.string("overlay.error.clipboardWrite", "The text could not be pasted or copied.")
            }
        let wayOut =
            switch error.remedy {
            case .permissions: L10n.string("overlay.remedy.permissions", "Open the Susurro menu to turn it on.")
            case .settings: L10n.string("overlay.remedy.settings", "Open the Susurro menu.")
            case .retry: L10n.string("overlay.remedy.retry", "Hold the key to try again.")
            case .check: L10n.string("overlay.remedy.check", "Check the app before you dictate again.")
            case .addKey: L10n.string("overlay.remedy.addKey", "Open the Susurro menu to add a key.")
            }
        return "\(headline) \(wayOut)"
    }
}
