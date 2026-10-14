import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Coordinator insertion target", .timeLimit(.minutes(1)))
struct CoordinatorTargetTests {
    @MainActor
    @Test("the text goes to the app that was in front when the key went down")
    func targetIsTheAppAtTheKeyDown() async {
        let frontmost = FakeFrontmostAppProvider(.mail)
        var h = await CoordinatorHarness(frontmost: frontmost)
        await h.sut.handle(.down(at: DictationCoordinatorTests.pressTime))
        frontmost.app = .slack  // the user switches apps while talking
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        _ = await h.read(through: .recording(.hold))

        _ = await h.release()

        #expect(h.inserter.targets == [.mail])
    }

    @Test("without a provider the text is inserted with no target")
    func noProvider() async {
        var h = await CoordinatorHarness()
        await h.startRecording()

        _ = await h.release()

        #expect(h.inserter.targets == [nil])
    }

    @Test("an insertion that times out names no retry, because the text may already be there")
    func timeoutIsUncertain() async {
        let sleeper = FakeSleeper(expiring: [DictationLimits.insertionTimeout])
        var h = await CoordinatorHarness(inserter: FakeTextInserter(gated: true), sleeper: sleeper)
        await h.startRecording()

        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .error(.timedOut(.insertion)), .idle])
        #expect(PipelineError.timedOut(.insertion).remedy == .check)
    }
}
