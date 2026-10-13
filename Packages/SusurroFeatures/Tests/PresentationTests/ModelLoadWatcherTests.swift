import CoreTestSupport
import Domain
import Testing

@testable import Presentation

@Suite("Model load watcher", .timeLimit(.minutes(1)))
struct ModelLoadWatcherTests {
    /// A watcher wired to a sleeper the test controls and to a record of the progress it reports.
    private struct Harness {
        let watcher: ModelLoadWatcher
        let sleeper: FakeSleeper
        var reports: AsyncStream<Double?>.Iterator

        init() async {
            let (stream, continuation) = AsyncStream.makeStream(of: Double?.self)
            let sleeper = FakeSleeper()
            self.sleeper = sleeper
            watcher = await MainActor.run {
                ModelLoadWatcher(
                    showAfter: ModelLoadWatcher.standardDelay,
                    sleep: { try await sleeper.sleep($0) },
                    report: { continuation.yield($0) }
                )
            }
            reports = stream.makeAsyncIterator()
        }

        func settle() async {
            for _ in 0..<50 { await Task.yield() }
        }

        mutating func nextReport() async -> Double?? {
            await reports.next()
        }
    }

    private static let delay = ModelLoadWatcher.standardDelay

    @Test("the delay is long enough that a load from the disk cache never shows, and not so long that a download hides")
    func delayRange() {
        #expect(Self.delay >= .seconds(1))
        #expect(Self.delay <= .seconds(3))
    }

    @Test("a load that ends before the delay is never shown")
    func quickLoadIsInvisible() async {
        var h = await Harness()
        await h.watcher.observe(.loading(progress: 0))
        await h.watcher.observe(.loading(progress: 0.5))
        await h.watcher.observe(.ready)
        h.sleeper.fire(Self.delay)  // too late: the delay was cancelled with the load
        await h.settle()
        await h.watcher.observe(.loading(progress: 0.1))  // a sentinel report that proves nothing came before it
        h.sleeper.fire(Self.delay)

        #expect(await h.nextReport() == .some(0.1))
    }

    @Test("a load that lasts past the delay reports the latest progress, then each change, then the end")
    func slowLoadIsShown() async {
        var h = await Harness()
        await h.watcher.observe(.loading(progress: 0))
        await h.watcher.observe(.loading(progress: 0.3))
        h.sleeper.fire(Self.delay)

        #expect(await h.nextReport() == .some(0.3))
        await h.watcher.observe(.loading(progress: 0.6))
        #expect(await h.nextReport() == .some(0.6))
        await h.watcher.observe(.ready)
        #expect(await h.nextReport() == .some(nil))
    }

    @Test("a load that fails before it is shown reports nothing")
    func failureBeforeItIsShown() async {
        var h = await Harness()
        await h.watcher.observe(.loading(progress: 0.2))
        await h.watcher.observe(.unavailable("offline", retryable: true))
        h.sleeper.fire(Self.delay)
        await h.settle()
        await h.watcher.observe(.loading(progress: 0.9))  // a retry, whose report is the first one

        #expect(await h.nextReport() == .some(0.9))
    }

    @Test("a load that fails after it was shown ends the display")
    func failureAfterItIsShown() async {
        var h = await Harness()
        await h.watcher.observe(.loading(progress: 0.2))
        h.sleeper.fire(Self.delay)
        #expect(await h.nextReport() == .some(0.2))

        await h.watcher.observe(.unavailable("offline", retryable: true))

        #expect(await h.nextReport() == .some(nil))
    }

    @Test("run applies each readiness the recognizer reports")
    func runConsumesTheStream() async {
        var h = await Harness()
        let (readiness, continuation) = AsyncStream.makeStream(of: RecognizerReadiness.self)
        let watcher = h.watcher
        let running = Task { await watcher.run(readiness) }
        h.sleeper.fire(Self.delay)

        continuation.yield(.loading(progress: 0.5))
        #expect(await h.nextReport() == .some(0.5))
        continuation.yield(.ready)
        #expect(await h.nextReport() == .some(nil))
        continuation.finish()
        await running.value
    }
}
