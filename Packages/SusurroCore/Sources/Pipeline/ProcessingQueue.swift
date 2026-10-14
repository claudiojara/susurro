import Foundation

/// Runs the processing of finished recordings one at a time, in the order they were finished.
///
/// Recording may start while an earlier dictation is still being processed, but the texts must reach the user in the
/// order the dictations were spoken, and the speech model works on one clip at a time. So a finished recording becomes a
/// job here, and jobs run first in, first out. See ADR 0030.
///
/// A job is a closure that does the whole processing and returns how it ended. The queue emits `jobEnqueued` when a job
/// is queued and `jobFinished` exactly once when it ends, whichever way: done, no speech, failed, or cancelled, a
/// cancelled job that never started included. Both carry the number of jobs in flight after the change, which the
/// dictation coordinator uses to arm and disarm Esc.
public actor ProcessingQueue {
    /// How a job ended.
    public enum Outcome: Sendable, Equatable {
        case succeeded
        case noSpeech
        case failed
        case cancelled
    }

    public enum Event: Sendable, Equatable {
        case jobEnqueued(UUID, inFlight: Int)
        case jobFinished(UUID, Outcome, inFlight: Int)
    }

    /// The processing of one recording. It checks `Task.isCancelled` at its stage boundaries; the queue cancels its task
    /// when the job is cancelled.
    public typealias Work = @Sendable () async -> Outcome

    private struct Job {
        let id: UUID
        let work: Work
    }

    /// The events, in order. Read it from one place: it is a single stream.
    public nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private var waiting: [Job] = []
    private var running: (id: UUID, task: Task<Outcome, Never>)?
    private var cancelledWhileRunning: Set<UUID> = []
    private var worker: Task<Void, Never>?
    private var drainers: [CheckedContinuation<Void, Never>] = []

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        continuation.finish()
    }

    /// The jobs that are running or waiting.
    public var inFlightCount: Int { waiting.count + (running == nil ? 0 : 1) }

    /// Queues a job behind the ones already there. An id that is already in flight is ignored.
    public func enqueue(_ id: UUID, work: @escaping Work) {
        guard !isInFlight(id) else { return }
        waiting.append(Job(id: id, work: work))
        continuation.yield(.jobEnqueued(id, inFlight: inFlightCount))
        if worker == nil { worker = Task { await self.runJobs() } }
    }

    /// Cancels a job. A job that is waiting never starts, and the jobs ahead of it are not affected. The running job gets
    /// its task cancelled and is reported cancelled when it returns. An id that is not in flight is ignored.
    public func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) {
            waiting.remove(at: index)
            finish(id, .cancelled)
        } else if let running, running.id == id {
            cancelledWhileRunning.insert(id)
            running.task.cancel()
        }
    }

    /// Cancels the job that was queued last: the dictation the user just spoke and that Esc is meant for. When none is
    /// waiting, it is the running one.
    public func cancelNewest() {
        if let newest = waiting.last {
            cancel(newest.id)
        } else if let running {
            cancel(running.id)
        }
    }

    /// Cancels every job, for a shutdown.
    public func cancelAll() {
        for job in waiting { cancel(job.id) }
        if let running { cancel(running.id) }
    }

    /// Returns once no job is in flight.
    public func drain() async {
        while inFlightCount > 0 {
            await withCheckedContinuation { drainers.append($0) }
        }
    }

    // MARK: Running

    private func isInFlight(_ id: UUID) -> Bool {
        running?.id == id || waiting.contains { $0.id == id }
    }

    private func runJobs() async {
        while !waiting.isEmpty {
            let job = waiting.removeFirst()
            let task = Task { await job.work() }
            running = (job.id, task)
            let outcome = await task.value
            running = nil
            finish(job.id, cancelledWhileRunning.remove(job.id) == nil ? outcome : .cancelled)
        }
        // Nothing suspends between the check of the loop and this, so a job queued meanwhile is never left without a
        // worker.
        worker = nil
    }

    private func finish(_ id: UUID, _ outcome: Outcome) {
        continuation.yield(.jobFinished(id, outcome, inFlight: inFlightCount))
        guard inFlightCount == 0 else { return }
        let waiters = drainers
        drainers = []
        for waiter in waiters { waiter.resume() }
    }
}
