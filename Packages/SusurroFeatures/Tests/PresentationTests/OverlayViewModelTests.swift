import DesignSystem
import Domain
import SusurroUI
import Testing

@testable import Presentation

@Suite("Overlay view model", .timeLimit(.minutes(1)))
struct OverlayViewModelTests {
    private static let anError = PipelineError.recognitionFailed("engine")

    @Test("the states of a dictation show as they come, and idle hides the indicator")
    func statesShowAndHide() async {
        var h = await OverlayHarness()
        await h.model.apply(.starting)
        await h.model.apply(.recording(.hold))
        await h.model.apply(.transcribing(progress: nil))
        await h.model.apply(.idle)

        #expect(h.message(of: await h.nextDisplay()) == "Getting ready…")
        #expect(h.message(of: await h.nextDisplay()) == "Listening…")
        #expect(h.message(of: await h.nextDisplay()) == "Transcribing…")
        #expect(await h.nextDisplay() == .hidden)
        #expect(await h.model.state.isHidden)
    }

    @Test("a state that shows the same indicator again does not redisplay it")
    func noDuplicateDisplay() async {
        var h = await OverlayHarness()
        await h.model.apply(.transcribing(progress: nil))
        await h.model.apply(.transcribing(progress: nil))
        await h.model.apply(.idle)

        #expect(h.message(of: await h.nextDisplay()) == "Transcribing…")
        #expect(await h.nextDisplay() == .hidden)  // the next display is the hide, not a repeat
    }

    @Test("inserted is held for its dwell even though idle follows at once")
    func insertedIsHeld() async {
        var h = await OverlayHarness()
        await h.model.apply(.inserted)
        await h.model.apply(.idle)
        await h.settle()

        #expect(await h.model.state.text == "Pasted")
        h.sleeper.fire(h.timing.inserted)
        #expect(h.message(of: await h.nextDisplay()) == "Pasted")
        #expect(await h.nextDisplay() == .hidden)
        #expect(await h.model.state.isHidden)
    }

    @Test("an error is still showing when the success delay has passed, and hides after its own")
    func errorOutlastsSuccess() async {
        var h = await OverlayHarness()
        await h.model.apply(.error(Self.anError))
        await h.model.apply(.idle)
        h.sleeper.fire(h.timing.inserted)
        await h.settle()

        #expect(await h.model.state.tint == .error)
        h.sleeper.fire(h.timing.error)
        #expect(h.message(of: await h.nextDisplay()) != nil)
        #expect(await h.nextDisplay() == .hidden)
    }

    @Test("a notice is held for its dwell, and the states that follow it wait their turn")
    func noticeHoldsThroughTranscribing() async {
        var h = await OverlayHarness()
        await h.model.apply(.notice(.capReached))
        await h.model.apply(.transcribing(progress: nil))
        await h.settle()

        #expect(await h.model.state.text == "Recording limit reached. Transcribing what was said…")
        h.sleeper.fire(h.timing.notice)
        _ = await h.nextDisplay()
        #expect(h.message(of: await h.nextDisplay()) == "Transcribing…")
    }

    @Test("a result that arrives while a notice is held waits, and then gets its own dwell")
    func resultWaitsForTheNotice() async {
        var h = await OverlayHarness()
        await h.model.apply(.notice(.capReached))
        await h.model.apply(.transcribing(progress: nil))
        await h.model.apply(.inserted)
        await h.model.apply(.idle)
        h.sleeper.fire(h.timing.notice)
        _ = await h.nextDisplay()  // the notice

        #expect(h.message(of: await h.nextDisplay()) == "Pasted")
        h.sleeper.fire(h.timing.inserted)
        #expect(await h.nextDisplay() == .hidden)
    }

    @Test("a result that waits behind a held indicator is not replaced by the idle state that follows it")
    func waitingResultSurvivesIdle() async {
        var h = await OverlayHarness()
        await h.model.apply(.notice(.capReached))
        await h.model.apply(.inserted)
        await h.model.apply(.idle)
        h.sleeper.fire(h.timing.notice)
        _ = await h.nextDisplay()  // the notice

        #expect(h.message(of: await h.nextDisplay()) == "Pasted")
    }

    @Test("a second result replaces the one that waits")
    func laterResultReplacesTheWaitingOne() async {
        var h = await OverlayHarness()
        await h.model.apply(.notice(.capReached))
        await h.model.apply(.inserted)
        await h.model.apply(.notice(.noSpeech))
        h.sleeper.fire(h.timing.notice)
        _ = await h.nextDisplay()  // the first notice

        #expect(h.message(of: await h.nextDisplay()) == "No speech heard")
    }

    @Test("of the states that wait behind a held indicator, the latest is the one that shows")
    func latestDeferredStateWins() async {
        var h = await OverlayHarness()
        await h.model.apply(.inserted)
        await h.model.apply(.transcribing(progress: 0.2))
        await h.model.apply(.transcribing(progress: 0.4))
        h.sleeper.fire(h.timing.inserted)
        _ = await h.nextDisplay()  // inserted

        #expect(h.message(of: await h.nextDisplay()) == "Preparing the speech model… 40%")
    }

    @Test("idle behind a held indicator hides it when the dwell ends")
    func idleBehindAHeldIndicator() async {
        var h = await OverlayHarness()
        await h.model.apply(.inserted)
        await h.model.apply(.transcribing(progress: 0.2))
        await h.model.apply(.idle)
        h.sleeper.fire(h.timing.inserted)
        _ = await h.nextDisplay()  // inserted

        #expect(await h.nextDisplay() == .hidden)
    }

    @Test(
        "an error and a new recording replace a held indicator at once",
        arguments: [
            (
                PipelineState.error(PipelineError.recognitionFailed("engine")),
                "Transcription failed. Hold the key to try again."
            ),
            (.starting, "Getting ready…"),
            (.recording(.hold), "Listening…"),
        ]
    )
    func preemption(state: PipelineState, message: String) async {
        var h = await OverlayHarness()
        await h.model.apply(.notice(.capReached))
        _ = await h.nextDisplay()
        await h.model.apply(state)

        #expect(h.message(of: await h.nextDisplay()) == message)
        #expect(await h.model.state.text == message)
    }

    @Test("a held indicator that was replaced does not hide the one that replaced it when its dwell ends")
    func replacedHoldDoesNotHideTheNewIndicator() async {
        var h = await OverlayHarness()
        await h.model.apply(.inserted)
        await h.model.apply(.error(Self.anError))
        h.sleeper.fire(h.timing.inserted)  // the dwell of the indicator that was replaced
        await h.settle()

        #expect(await h.model.state.tint == .error)
        h.sleeper.fire(h.timing.error)
        _ = await h.nextDisplay()  // inserted
        _ = await h.nextDisplay()  // error
        #expect(await h.nextDisplay() == .hidden)
    }

    @Test("a result waits behind a notice")
    func resultWaitsBehindANotice() async {
        var h = await OverlayHarness()
        await h.model.apply(.notice(.noSpeech))
        await h.model.apply(.inserted)
        await h.settle()

        #expect(await h.model.state.text == "No speech heard")
    }

    // MARK: Model unavailable

    @Test("a model that is unavailable shows a warning for the error dwell, in place of the progress, and then hides")
    func modelUnavailableWarns() async {
        var h = await OverlayHarness()
        await h.model.setModelProgress(0.4)
        await h.model.showModelUnavailable()
        await h.settle()

        #expect(await h.model.state.text == "Speech model unavailable. Open the Susurro menu for details.")
        h.sleeper.fire(h.timing.error)
        #expect(h.message(of: await h.nextDisplay()) == "Preparing the speech model… 40%")
        let warning = await h.nextDisplay()
        #expect(warning?.tint == .warning)
        #expect(await h.nextDisplay() == .hidden)
        #expect(await h.model.state.isHidden)
    }

    @Test("the unavailable warning does not cover a dictation, and does not come back after it")
    func modelUnavailableYieldsToADictation() async {
        var h = await OverlayHarness()
        await h.model.apply(.recording(.hold))
        await h.model.showModelUnavailable()
        await h.model.apply(.idle)

        #expect(h.message(of: await h.nextDisplay()) == "Listening…")
        #expect(await h.nextDisplay() == .hidden)
        #expect(await h.model.state.isHidden)
    }

    @Test("a dictation that starts during the unavailable warning replaces it")
    func dictationReplacesTheUnavailableWarning() async {
        var h = await OverlayHarness()
        await h.model.showModelUnavailable()
        await h.model.apply(.starting)

        _ = await h.nextDisplay()  // the warning
        #expect(h.message(of: await h.nextDisplay()) == "Getting ready…")
    }

    // MARK: Model load progress while idle

    @Test("model load progress shows while the pipeline is idle, and hides when the load ends")
    func modelProgressWhileIdle() async {
        var h = await OverlayHarness()
        await h.model.setModelProgress(0.3)
        await h.model.setModelProgress(0.6)
        await h.model.setModelProgress(nil)

        let first = await h.nextDisplay()
        #expect(first?.progress == 0.3)
        #expect(h.message(of: first) == "Preparing the speech model… 30%")
        #expect(h.message(of: await h.nextDisplay()) == "Preparing the speech model… 60%")
        #expect(await h.nextDisplay() == .hidden)
    }

    @Test("a dictation takes over from the model progress, which comes back when the pipeline is idle again")
    func dictationOverModelProgress() async {
        var h = await OverlayHarness()
        await h.model.setModelProgress(0.3)
        await h.model.apply(.recording(.hold))
        await h.model.setModelProgress(0.5)  // stored, not shown: a recording is on screen
        let whileRecording = await h.model.state.text
        await h.model.apply(.idle)

        _ = await h.nextDisplay()  // 30%
        #expect(h.message(of: await h.nextDisplay()) == "Listening…")
        #expect(h.message(of: await h.nextDisplay()) == "Preparing the speech model… 50%")
        #expect(whileRecording == "Listening…")
    }

    @Test("model progress waits behind a held indicator and shows when its dwell ends")
    func modelProgressBehindAHold() async {
        var h = await OverlayHarness()
        await h.model.apply(.inserted)
        await h.model.setModelProgress(0.7)
        await h.model.apply(.idle)
        h.sleeper.fire(h.timing.inserted)
        _ = await h.nextDisplay()  // inserted

        #expect(h.message(of: await h.nextDisplay()) == "Preparing the speech model… 70%")
    }

    // MARK: Consuming the pipeline's states

    @Test("run shows each state the pipeline publishes, in order, until the stream ends")
    func runConsumesTheStream() async {
        var h = await OverlayHarness()
        let (states, continuation) = AsyncStream.makeStream(of: PipelineState.self)
        for state in [PipelineState.idle, .starting, .recording(.hold), .idle] { continuation.yield(state) }
        continuation.finish()

        await h.model.run(states: states)

        #expect(h.message(of: await h.nextDisplay()) == "Getting ready…")
        #expect(h.message(of: await h.nextDisplay()) == "Listening…")
        #expect(await h.nextDisplay() == .hidden)
    }

    @Test("a notice from outside the pipeline shows while it is idle, and holds for the notice dwell")
    func externalNotice() async {
        var h = await OverlayHarness()
        await h.model.showNotice(.noLastDictation)

        #expect(h.message(of: await h.nextDisplay()) == "No dictation to paste yet")
        h.sleeper.fire(h.timing.notice)
        #expect(await h.nextDisplay() == .hidden)
    }

    @Test("a notice from outside the pipeline does not cover a dictation under way")
    func externalNoticeDuringDictation() async {
        var h = await OverlayHarness()
        await h.model.apply(.recording(.hold))
        #expect(h.message(of: await h.nextDisplay()) == "Listening…")

        await h.model.showNotice(.noLastDictation)

        #expect(await h.model.state.text == "Listening…")
    }
}
