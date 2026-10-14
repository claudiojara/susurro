import Domain
import Testing

@testable import Presentation

@Suite("Overlay indicator mapping")
struct OverlayIndicatorTests {
    @Test("an idle pipeline shows nothing")
    func idleShowsNothing() {
        #expect(OverlayIndicator.indicator(for: .idle) == nil)
    }

    @Test(
        "each active state has a tone and a message",
        arguments: [
            (PipelineState.starting, OverlayIndicator.Tone.neutral, "Getting ready…"),
            (.recording(.hold), .recording, "Listening…"),
            (.transcribing(progress: nil), .neutral, "Transcribing…"),
            (.inserted, .success, "Pasted"),
        ]
    )
    func activeStates(state: PipelineState, tone: OverlayIndicator.Tone, message: String) {
        let indicator = OverlayIndicator.indicator(for: state)

        #expect(indicator?.tone == tone)
        #expect(indicator?.message == message)
        #expect(indicator?.progress == nil)
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
        let indicator = OverlayIndicator.indicator(for: .transcribing(progress: progress))

        #expect(indicator?.message == "Preparing the speech model… \(percent)")
        #expect(indicator?.progress == fraction)
        #expect(indicator?.tone == .neutral)
    }

    @Test("the model indicator while idle reads like the one while waiting for the model")
    func modelIndicatorMatchesTheWait() {
        #expect(OverlayIndicator.modelLoading(progress: 0.3) == .indicator(for: .transcribing(progress: 0.3)))
    }

    @Test("a model that is unavailable shows a warning that names the menu")
    func modelUnavailable() {
        let indicator = OverlayIndicator.modelUnavailable

        #expect(indicator.message == "Speech model unavailable. Open the Susurro menu for details.")
        #expect(indicator.tone == .warning)
        #expect(indicator.progress == nil)
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
            (.deviceDisconnected, "The microphone was disconnected. Transcribing what was recorded…"),
            (.silentMicrophone, "The microphone seems to be silent. Check that it is not muted."),
        ]
    )
    func notices(kind: NoticeKind, message: String) {
        let indicator = OverlayIndicator.indicator(for: .notice(kind))

        #expect(indicator?.message == message)
        #expect(indicator?.tone == .warning)
    }

    @Test(
        "each error says what failed and names the way out",
        arguments: [
            (PipelineError.microphoneNotGranted, "Microphone access is off. Open the Susurro menu to turn it on."),
            (.recognizerNotInstalled, "The speech model is missing. Open the Susurro menu."),
            (
                .recognizerUnavailable("offline", retryable: true),
                "The speech model could not load. Hold the key to try again."
            ),
            (
                .recognizerUnavailable("damaged", retryable: false),
                "The speech model could not load. Open the Susurro menu."
            ),
            (.captureFailed("device"), "Could not record. Hold the key to try again."),
            (.persistenceFailed("disk"), "Could not save the recording. Hold the key to try again."),
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
        let indicator = OverlayIndicator.indicator(for: .error(error))

        #expect(indicator?.message == message)
        #expect(indicator?.tone == .error)
    }

    @Test("the error text never repeats the reason the system gave, which can quote what was said")
    func errorsCarryNoSystemText() {
        let secret = "the user said hunter2"
        let errors: [PipelineError] = [
            .recognizerUnavailable(secret, retryable: true), .captureFailed(secret), .recognitionFailed(secret),
            .persistenceFailed(secret),
        ]

        for error in errors {
            #expect(OverlayIndicator.indicator(for: .error(error))?.message.contains("hunter2") == false)
        }
    }
}
