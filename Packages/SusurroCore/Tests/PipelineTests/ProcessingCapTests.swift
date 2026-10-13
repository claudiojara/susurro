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
        // Only the cap expires, not the transcription limit, so the error can only come from the cap.
        let sleeper = FakeSleeper(expiring: [DictationLimits.processingCap])
        var h = await Harness(recognizer: FakeRecognizer(gated: true), sleeper: sleeper)
        await h.startRecording()

        #expect(await h.release() == [.transcribing(progress: nil), .error(.timedOut(.transcription)), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("an insertion that has not finished when the cap runs out ends in an error naming that stage")
    func capEndsAnInsertion() async {
        let sleeper = FakeSleeper(expiring: [DictationLimits.processingCap])
        var h = await Harness(inserter: FakeTextInserter(gated: true), sleeper: sleeper)
        await h.startRecording()

        #expect(await h.release() == [.transcribing(progress: nil), .error(.timedOut(.insertion)), .idle])
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("a wait for the model that has not finished when the cap runs out ends in an error naming that stage")
    func capEndsTheWaitForTheModel() async {
        // Every pause blocks, so the wait cannot reach its own limits and only the cap can end it.
        let recognizer = FakeRecognizer(readiness: [.loading(progress: 0.5)])
        var h = await Harness(
            recognizer: recognizer,
            sleeper: FakeSleeper(expiring: [DictationLimits.processingCap], blocksPauses: true))
        await h.startRecording()
        let states = await h.release()

        #expect(
            states == [
                .transcribing(progress: nil), .transcribing(progress: 0.5), .error(.timedOut(.readiness)), .idle,
            ])
        #expect(recognizer.transcribedClips.isEmpty)
    }

    @Test("a press after a capped dictation starts a new recording")
    func nextPressWorksAfterTheCap() async {
        let sleeper = FakeSleeper(expiring: [DictationLimits.processingCap])
        var h = await Harness(recognizer: FakeRecognizer(gated: true), sleeper: sleeper)
        await h.startRecording()
        let capped = await h.release()
        await h.startRecording()  // reaches the recording state only if the coordinator is idle again

        #expect(capped.suffix(2) == [.error(.timedOut(.transcription)), .idle])
        #expect(h.capture.startCount == 2)
    }
}
