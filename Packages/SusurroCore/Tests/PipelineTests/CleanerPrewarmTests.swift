import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing

/// Counts the times the coordinator asked for the cleaner to get ready. The warm-up can be held until the test lets it
/// go, to show that the recording does not wait for it.
private final class PrewarmSpy: Sendable {
    private let calls = Mutex(0)
    let entered = Gate()
    private let hold: Gate?

    init(held: Bool = false) {
        hold = held ? Gate() : nil
    }

    var count: Int { calls.withLock { $0 } }
    func letGo() { hold?.open() }

    func prewarm() async {
        calls.withLock { $0 += 1 }
        entered.open()
        await hold?.wait()
    }
}

@Suite("Cleaner prewarm", .timeLimit(.minutes(1)))
struct CleanerPrewarmTests {
    @Test("the key going down gets the cleaner ready once")
    func keyDownWarms() async {
        let spy = PrewarmSpy()
        var h = await CoordinatorHarness(prewarmCleaner: { await spy.prewarm() })
        await h.startRecording()
        await spy.entered.wait()
        #expect(spy.count == 1)
        #expect(await h.release(after: 1_200) == DictationCoordinatorTests.transcribed)
        #expect(spy.count == 1)
    }

    @Test("a short hold that is discarded got the cleaner ready too, which costs nothing")
    func discardedHoldWarms() async {
        let spy = PrewarmSpy()
        var h = await CoordinatorHarness(prewarmCleaner: { await spy.prewarm() })
        await h.startRecording()
        await spy.entered.wait()
        #expect(await h.release(after: 80) == [.idle])
        #expect(spy.count == 1)
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    @Test("a warm-up that is slow does not hold the recording back")
    func slowWarmUpDoesNotDelay() async {
        let spy = PrewarmSpy(held: true)
        var h = await CoordinatorHarness(prewarmCleaner: { await spy.prewarm() })
        await h.startRecording()  // reaches .recording while the warm-up is still held
        await spy.entered.wait()
        #expect(h.capture.startCount == 1)
        spy.letGo()
        #expect(await h.release(after: 1_200) == DictationCoordinatorTests.transcribed)
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("without a warm-up closure the key going down works as before")
    func noClosure() async {
        var h = await CoordinatorHarness()
        await h.startRecording()
        #expect(await h.release(after: 1_200) == DictationCoordinatorTests.transcribed)
    }
}
