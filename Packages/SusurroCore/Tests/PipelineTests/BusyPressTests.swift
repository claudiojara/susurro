import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Presses while a dictation is processing", .timeLimit(.minutes(1)))
struct BusyPressTests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime

    @Test("every ignored press says so, and the dictation carries on unchanged")
    func eachIgnoredPressIsReported() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "uno", gated: true))
        await h.startProcessing()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(1400)))
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1500)))
        h.recognizer.releaseTranscription()

        let busy: [PipelineState] = [.notice(.busy), .transcribing(progress: nil)]
        #expect(await h.read(through: .idle) == busy + busy + [.inserted, .idle])
        #expect(h.capture.startCount == 1)
        #expect(h.inserter.insertedTexts == ["uno"])
    }

    @Test("a press while recording or starting stays silent, since the key is already down")
    func pressesBeforeProcessingStaySilent() async {
        var h = await Harness()
        await h.startRecording()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(500)))

        #expect(await h.release() == DictationCoordinatorTests.transcribed)
    }

    @Test("the pipeline is idle again after a busy press, and the next press records")
    func nextPressRecordsAfterBusyOne() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "uno", gated: true))
        await h.startProcessing()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        h.recognizer.releaseTranscription()
        h.recognizer.releaseTranscription()  // opens are remembered, so the second dictation passes the gate too
        _ = await h.read(through: .idle)
        await h.startRecording()
        let second = await h.release()

        #expect(second == DictationCoordinatorTests.transcribed)
        #expect(h.capture.startCount == 2)
    }
}
