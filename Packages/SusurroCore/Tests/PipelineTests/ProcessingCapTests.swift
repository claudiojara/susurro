import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Total processing time of one dictation", .timeLimit(.minutes(1)))
struct ProcessingCapTests {
    private typealias Harness = CoordinatorHarness

    @Test("the cap is shorter than its three stages together, and long enough for the slowest model load")
    func capFitsBetweenTheLimits() {
        let stages =
            DictationLimits.readinessHardCap + DictationLimits.transcriptionTimeout + DictationLimits.insertionTimeout

        #expect(DictationLimits.processingCap < stages)
        #expect(DictationLimits.processingCap >= DictationLimits.readinessHardCap)
    }

    @Test("a transcription that has not finished when the cap runs out ends in an error naming that stage")
    func capEndsATranscription() async {
        // The cap fires and the transcription limit does not, so the error can only come from the cap.
        var h = await Harness(recognizer: FakeRecognizer(gated: true))
        await h.startProcessing()
        await h.recognizer.transcribeEntered.wait()
        h.sleeper.fire(DictationLimits.processingCap)

        #expect(await h.read(through: .idle) == [.error(.timedOut(.transcription)), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("an insertion that has not finished when the cap runs out ends in an error naming that stage")
    func capEndsAnInsertion() async {
        var h = await Harness(inserter: FakeTextInserter(gated: true))
        await h.startProcessing()
        await h.inserter.entered.wait()
        h.sleeper.fire(DictationLimits.processingCap)

        #expect(await h.read(through: .idle) == [.error(.timedOut(.insertion)), .idle])
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("a wait for the model that has not finished when the cap runs out ends in an error naming that stage")
    func capEndsTheWaitForTheModel() async {
        // Every pause blocks, so the wait cannot reach its own limits and only the cap can end it.
        let recognizer = FakeRecognizer(readiness: [.loading(progress: 0.5)])
        var h = await Harness(recognizer: recognizer, sleeper: FakeSleeper(blocksPauses: true))
        await h.startRecording()
        await h.sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(1200)))
        _ = await h.read(through: .transcribing(progress: 0.5))
        h.sleeper.fire(DictationLimits.processingCap)

        #expect(await h.read(through: .idle) == [.error(.timedOut(.readiness)), .idle])
        #expect(recognizer.transcribedClips.isEmpty)
    }

    @Test("a dictation that finishes inside the cap is untouched by it")
    func capLeavesAFastDictationAlone() async {
        var h = await Harness()
        await h.startRecording()

        #expect(await h.release() == DictationCoordinatorTests.transcribed)
    }

    @Test("a press after a capped dictation starts a new recording")
    func nextPressWorksAfterTheCap() async {
        var h = await Harness(recognizer: FakeRecognizer(gated: true))
        await h.startProcessing()
        await h.recognizer.transcribeEntered.wait()
        h.sleeper.fire(DictationLimits.processingCap)
        let capped = await h.read(through: .idle)
        await h.startRecording()  // reaches the recording state only if the coordinator is idle again

        #expect(capped == [.error(.timedOut(.transcription)), .idle])
        #expect(h.capture.startCount == 2)
    }
}
