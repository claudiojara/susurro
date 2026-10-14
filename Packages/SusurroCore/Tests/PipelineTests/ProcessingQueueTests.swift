import CoreTestSupport
import Foundation
import Pipeline
import Synchronization
import Testing

@Suite("Processing queue", .timeLimit(.minutes(1)))
struct ProcessingQueueTests {
    /// What the jobs did, in order, as they did it.
    private final class Log: Sendable {
        private let lines = Mutex<[String]>([])
        var all: [String] { lines.withLock { $0 } }
        func add(_ line: String) { lines.withLock { $0.append(line) } }
    }

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    /// Reads events until `count` of them have come.
    private static func events(
        _ events: AsyncStream<ProcessingQueue.Event>, count: Int
    ) async -> [ProcessingQueue.Event] {
        var iterator = events.makeAsyncIterator()
        var collected: [ProcessingQueue.Event] = []
        while collected.count < count, let event = await iterator.next() { collected.append(event) }
        return collected
    }

    @Test("jobs run one at a time in the order they came: a slow A is done before a fast B starts")
    func firstInFirstOut() async {
        let queue = ProcessingQueue()
        let log = Log()
        let slow = Gate()
        await queue.enqueue(a) {
            log.add("A start")
            await slow.wait()
            log.add("A end")
            return .succeeded
        }
        await queue.enqueue(b) {
            log.add("B start")
            log.add("B end")
            return .succeeded
        }
        slow.open()

        let events = await Self.events(queue.events, count: 4)

        #expect(log.all == ["A start", "A end", "B start", "B end"])
        #expect(
            events == [
                .jobEnqueued(a, inFlight: 1), .jobEnqueued(b, inFlight: 2),
                .jobFinished(a, .succeeded, inFlight: 1), .jobFinished(b, .succeeded, inFlight: 0),
            ])
    }

    @Test("a cancelled job that is still waiting is skipped, and the older job ahead of it is not touched")
    func cancelledWaitingJobIsSkipped() async {
        let queue = ProcessingQueue()
        let log = Log()
        let slow = Gate()
        await queue.enqueue(a) {
            await slow.wait()
            log.add("A done")
            return .succeeded
        }
        await queue.enqueue(b) {
            log.add("B ran")
            return .succeeded
        }
        await queue.enqueue(c) {
            log.add("C ran")
            return .succeeded
        }

        await queue.cancel(b)
        slow.open()
        let events = await Self.events(queue.events, count: 6)

        #expect(log.all == ["A done", "C ran"])
        #expect(
            events.filter { if case .jobFinished = $0 { true } else { false } } == [
                .jobFinished(b, .cancelled, inFlight: 2),
                .jobFinished(a, .succeeded, inFlight: 1),
                .jobFinished(c, .succeeded, inFlight: 0),
            ])
    }

    @Test("cancelling the job that is running cancels its task and reports it cancelled, whatever it returns")
    func cancelRunningJob() async {
        let queue = ProcessingQueue()
        let started = Gate()
        let hold = Gate()
        await queue.enqueue(a) {
            started.open()
            await hold.wait()
            // The job ignores the cancellation and claims success: the queue still reports what the user asked for.
            return .succeeded
        }
        await queue.enqueue(b) { .succeeded }
        await started.wait()

        await queue.cancel(a)
        let events = await Self.events(queue.events, count: 4)

        #expect(
            events.suffix(2) == [.jobFinished(a, .cancelled, inFlight: 1), .jobFinished(b, .succeeded, inFlight: 0)])
    }

    @Test("every way a job can end emits one jobFinished, and the count of jobs in flight follows")
    func eachOutcomeFinishesOnce() async {
        let queue = ProcessingQueue()
        let ids = (0..<4).map { _ in UUID() }
        let outcomes: [ProcessingQueue.Outcome] = [.succeeded, .noSpeech, .failed, .cancelled]
        for (id, outcome) in zip(ids, outcomes) { await queue.enqueue(id) { outcome } }

        let events = await Self.events(queue.events, count: 8)
        await queue.drain()

        let finished = events.compactMap { event -> UUID? in
            if case .jobFinished(let id, _, _) = event { id } else { nil }
        }
        #expect(finished == ids)
        #expect(
            events.compactMap { event -> ProcessingQueue.Outcome? in
                if case .jobFinished(_, let outcome, _) = event { outcome } else { nil }
            } == outcomes)
        #expect(await queue.inFlightCount == 0)
    }

    @Test("the count of jobs in flight includes the one running and the ones waiting")
    func inFlightCount() async {
        let queue = ProcessingQueue()
        let hold = Gate()
        #expect(await queue.inFlightCount == 0)
        await queue.enqueue(a) {
            await hold.wait()
            return .succeeded
        }
        await queue.enqueue(b) { .succeeded }
        #expect(await queue.inFlightCount == 2)

        hold.open()
        await queue.drain()
        #expect(await queue.inFlightCount == 0)
    }

    @Test("cancelling the newest job takes the last one waiting, or the running one when none waits")
    func cancelNewest() async {
        let queue = ProcessingQueue()
        let log = Log()
        let hold = Gate()
        let started = Gate()
        await queue.enqueue(a) {
            started.open()
            await hold.wait()
            log.add("A")
            return .succeeded
        }
        await queue.enqueue(b) {
            log.add("B")
            return .succeeded
        }
        await started.wait()

        await queue.cancelNewest()
        hold.open()
        await queue.drain()
        #expect(log.all == ["A"])

        let started2 = Gate()
        let hold2 = Gate()
        await queue.enqueue(c) {
            started2.open()
            await hold2.wait()
            log.add("C")
            return .succeeded
        }
        await started2.wait()
        await queue.cancelNewest()
        await queue.drain()
        // Cancelling the running task opens the wait, so the job ends without anyone releasing it.
        #expect(log.all == ["A", "C"])
        #expect(await queue.inFlightCount == 0)
    }

    @Test("cancelling a job that is not in the queue does nothing, and an id already in flight is not queued twice")
    func unknownAndDuplicateIDs() async {
        let queue = ProcessingQueue()
        let hold = Gate()
        await queue.enqueue(a) {
            await hold.wait()
            return .succeeded
        }
        await queue.enqueue(a) { .failed }
        await queue.cancel(UUID())

        #expect(await queue.inFlightCount == 1)
        hold.open()
        let events = await Self.events(queue.events, count: 2)
        #expect(events == [.jobEnqueued(a, inFlight: 1), .jobFinished(a, .succeeded, inFlight: 0)])
    }

    @Test("cancelAll ends every job at once, for a shutdown")
    func cancelAll() async {
        let queue = ProcessingQueue()
        let hold = Gate()
        let started = Gate()
        await queue.enqueue(a) {
            started.open()
            await hold.wait()
            return .succeeded
        }
        await queue.enqueue(b) { .succeeded }
        await started.wait()

        await queue.cancelAll()
        await queue.drain()

        #expect(await queue.inFlightCount == 0)
    }
}
