import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing

@Suite("Dictation coordinator shutdown", .timeLimit(.minutes(1)))
struct CoordinatorShutdownTests {
    private typealias Harness = CoordinatorHarness

    /// Whether a task has finished, readable from the test without waiting for it.
    private final class Done: Sendable {
        private let flag = Mutex(false)
        var isSet: Bool { flag.withLock { $0 } }
        func set() { flag.withLock { $0 = true } }
    }

    /// Lets the other tasks run until they have had every chance to finish, so that "not yet" is observable.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test("shutdown waits for the inserter to finish the paste it still has in hand")
    func shutdownWaitsForTheDrain() async {
        let inserter = FakeTextInserter(gatedDrain: true)
        let h = await Harness(inserter: inserter)
        let sut = h.sut
        let done = Done()
        let shutdown = Task {
            await sut.shutdown()
            done.set()
        }
        await inserter.drainEntered.wait()
        await settle()
        let finishedEarly = done.isSet
        inserter.releaseDrain()
        await shutdown.value

        #expect(!finishedEarly)
        #expect(inserter.drainCount == 1)
    }

    @Test("shutdown drains the inserter after abandoning a paste that is under way")
    func shutdownDrainsAfterAbandoningAnInsertion() async {
        let inserter = FakeTextInserter(gated: true)
        var h = await Harness(inserter: inserter)
        await h.startRecording()
        await h.sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(1200)))
        await inserter.entered.wait()
        await h.sut.shutdown()

        #expect(inserter.drainCount == 1)
        #expect(inserter.insertedTexts == ["hello"])
        #expect(await h.read(through: .idle) == [.transcribing(progress: nil), .idle])
    }

    @Test("a drain that never returns is abandoned after its limit, and the shutdown still completes")
    func drainHasALimit() async {
        let inserter = FakeTextInserter(gatedDrain: true)
        var h = await Harness(inserter: inserter, sleeper: FakeSleeper(expiring: [DictationLimits.drainTimeout]))
        await h.startRecording()
        await h.sut.shutdown()

        #expect(inserter.drainCount == 1)
        #expect(h.diagnostics.events == [.shutdownDrainAbandoned])
        #expect(await h.read(through: .idle) == [.idle])
        #expect(await h.read(through: .starting).isEmpty)  // the state stream has ended
    }

    @Test("a drain that returns in time is not reported")
    func drainInTimeIsQuiet() async {
        let h = await Harness()
        await h.sut.shutdown()

        #expect(h.inserter.drainCount == 1)
        #expect(h.diagnostics.events.isEmpty)
    }

    @Test("concurrent shutdown callers all wait for the one shutdown")
    func concurrentCallersShareOneShutdown() async {
        let inserter = FakeTextInserter(gatedDrain: true)
        var h = await Harness(inserter: inserter)
        await h.startRecording()
        let sut = h.sut
        let first = Done()
        let second = Done()
        let firstCaller = Task {
            await sut.shutdown()
            first.set()
        }
        await inserter.drainEntered.wait()
        let secondCaller = Task {
            await sut.shutdown()
            second.set()
        }
        await settle()
        let earlyFlags = (first.isSet, second.isSet)
        inserter.releaseDrain()
        await firstCaller.value
        await secondCaller.value

        #expect(earlyFlags == (false, false))
        #expect(inserter.drainCount == 1)
        #expect(h.capture.stopCount == 1)
        #expect(await h.read(through: .idle) == [.idle])
    }

    @Test("a shutdown that is already finished returns at once, and nothing runs twice")
    func shutdownTwiceInARow() async {
        let h = await Harness()
        await h.sut.shutdown()
        await h.sut.shutdown()

        #expect(h.inserter.drainCount == 1)
    }
}
