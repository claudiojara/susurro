import DesignSystem
import Domain
import SusurroUI
import Testing

@testable import Presentation

@Suite("Overlay mapping")
struct OverlayMappingTests {
    @Test("an idle pipeline shows nothing")
    func idleShowsNothing() {
        #expect(OverlayMapping.viewState(for: .idle) == .hidden)
    }

    @Test(
        "each active state has a tint and a message",
        arguments: [
            (PipelineState.starting, Tint.neutral, "Getting ready…"),
            (.recording(.hold), .recording, "Listening…"),
            (.transcribing(progress: nil), .neutral, "Transcribing…"),
            (.inserted, .success, "Pasted"),
        ]
    )
    func activeStates(state: PipelineState, tint: Tint, message: String) {
        let mapped = OverlayMapping.viewState(for: state)

        #expect(mapped.tint == tint)
        #expect(mapped.text == message)
        #expect(mapped.progress == nil)
    }

    @Test("starting shows until the first buffer arrives, and then recording")
    func readyGating() {
        #expect(OverlayMapping.viewState(for: .starting) == .starting(text: "Getting ready…"))
        #expect(
            OverlayMapping.viewState(for: .recording(.hold))
                == .recording(handsFree: false, text: "Listening…", hint: nil))
    }

    @Test("a hands-free recording sets the flag and tells how to stop")
    func handsFree() {
        let mapped = OverlayMapping.viewState(for: .recording(.handsFree))

        #expect(mapped == .recording(handsFree: true, text: "Listening…", hint: OverlayMapping.handsFreeHint))
        #expect(OverlayMapping.handsFreeHint.contains("again"))
        #expect(OverlayMapping.handsFreeHint.contains("Esc"))
    }

    @Test("a cap notice maps to a notice that says the limit was reached")
    func capNotice() {
        let mapped = OverlayMapping.viewState(for: .notice(.capReached))

        guard case .notice = mapped else {
            Issue.record("Expected a notice, got \(mapped)")
            return
        }
        #expect(mapped.text == "Recording limit reached. Transcribing what was said…")
    }

    @Test(
        "model load progress shows as a percentage and a bar, and progress that is not a number counts as none",
        arguments: [
            (0.0, "0%", 0.0), (0.42, "42%", 0.42), (0.29, "29%", 0.29), (0.994, "99%", 0.994), (1.0, "100%", 1.0),
            (-0.5, "0%", 0.0), (1.7, "100%", 1.0), (Double.nan, "0%", 0.0), (Double.infinity, "0%", 0.0),
            (-Double.infinity, "0%", 0.0),
        ]
    )
    func loadProgress(progress: Double, percent: String, fraction: Double) {
        let mapped = OverlayMapping.viewState(for: .transcribing(progress: progress))

        #expect(mapped.text == "Preparing the speech model… \(percent)")
        #expect(mapped.progress == fraction)
        #expect(mapped.tint == .neutral)
    }

    @Test("the model state while idle reads like the one while waiting for the model")
    func modelStateMatchesTheWait() {
        #expect(
            OverlayMapping.modelLoading(progress: 0.3) == OverlayMapping.viewState(for: .transcribing(progress: 0.3)))
    }

    @Test("a model that is unavailable shows a warning that names the menu")
    func modelUnavailable() {
        let mapped = OverlayMapping.modelUnavailable

        #expect(mapped.text == "Speech model unavailable. Open the Susurro menu for details.")
        #expect(mapped.tint == .warning)
        #expect(mapped.progress == nil)
    }

    @Test(
        "each notice says what happened",
        arguments: [
            (NoticeKind.noSpeech, "No speech heard"),
            (.capReached, "Recording limit reached. Transcribing what was said…"),
            (
                .copiedToClipboard(.accessibilityMissing),
                "Copied to the clipboard. Turn on Accessibility in the Susurro menu to paste automatically."
            ),
            (.copiedToClipboard(.pasteFailed), "Copied to the clipboard. Paste it with Command-V."),
            (.busy, "Still working on the last dictation"),
        ]
    )
    func notices(kind: NoticeKind, message: String) {
        let mapped = OverlayMapping.viewState(for: .notice(kind))

        #expect(mapped.text == message)
        #expect(mapped.tint == .warning)
    }

    @Test(
        "each error says what failed and names the way out",
        arguments: [
            (PipelineError.microphoneNotGranted, "Microphone access is off. Open the Susurro menu to turn it on."),
            (.recognizerNotInstalled, "The speech model is missing. Open the Susurro menu."),
            (.cloudKeyMissing, "The speech service has no API key. Open the Susurro menu to add a key."),
            (
                .recognizerUnavailable("offline", retryable: true),
                "The speech model could not load. Hold the key to try again."
            ),
            (
                .recognizerUnavailable("damaged", retryable: false),
                "The speech model could not load. Open the Susurro menu."
            ),
            (.captureFailed("device"), "Could not record. Hold the key to try again."),
            (.recognitionFailed("engine"), "Transcription failed. Hold the key to try again."),
            (.timedOut(.readiness), "The speech model is taking too long to load. Hold the key to try again."),
            (.timedOut(.capture), "The microphone did not stop in time. Hold the key to try again."),
            (.timedOut(.transcription), "Transcription took too long. Hold the key to try again."),
            (.timedOut(.insertion), "Pasting took too long. Hold the key to try again."),
            (
                .notInserted(.clipboardChanged),
                "Not pasted: the clipboard changed meanwhile. Hold the key to try again."
            ),
            (.notInserted(.clipboardWriteFailed), "The text could not be pasted or copied. Hold the key to try again."),
        ]
    )
    func errors(error: PipelineError, message: String) {
        let mapped = OverlayMapping.viewState(for: .error(error))

        #expect(mapped == .error(text: message))
        #expect(mapped.tint == .error)
    }

    @Test("the error text never repeats the reason the system gave, which can quote what was said")
    func errorsCarryNoSystemText() {
        let secret = "the user said hunter2"
        let errors: [PipelineError] = [
            .recognizerUnavailable(secret, retryable: true), .captureFailed(secret), .recognitionFailed(secret),
        ]

        for error in errors {
            #expect(OverlayMapping.viewState(for: .error(error)).text?.contains("hunter2") == false)
        }
    }
}
