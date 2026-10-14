import Synchronization

/// A clock for tests that moves only when the test calls `advance(by:)`. A sleep suspends until the clock reaches its
/// deadline, so a test decides when each timer fires. Sleeps whose deadlines are reached by one advance wake in
/// deadline order, and sleeps with the same deadline in the order they were called. Like `Task.sleep`, a sleep throws
/// `CancellationError` when its task is cancelled, and removes itself from the clock.
///
/// A test that starts the code under test waits with `waitForSleeps(_:)` until the sleep has been suspended, and only
/// then advances, so the advance cannot run before the sleep it is meant to end.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol {
        /// The time since the clock was created.
        public let offset: Duration

        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Waiter {
        let call: Int
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var offset = Duration.zero
        /// The sleeps asked for, which numbers each one.
        var calls = 0
        var suspended = 0
        var waiters: [Waiter] = []
        var wakeOrder: [Int] = []
        var watchers: [(total: Int, gate: Gate)] = []
    }

    private enum Entry {
        case cancelled
        case due
        case suspended(opening: [Gate])
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { Instant(offset: state.withLock { $0.offset }) }
    public var minimumResolution: Duration { .nanoseconds(1) }

    /// The sleeps that are suspended now.
    public var pendingSleeps: Int { state.withLock { $0.waiters.count } }
    /// The sleeps that have been suspended since the clock was created, woken or cancelled ones included.
    public var suspendedSleeps: Int { state.withLock { $0.suspended } }
    /// The sleeps the clock has woken, as the numbers their calls got (from 0, in the order of the calls), in the order
    /// it woke them. A cancelled sleep is not in it.
    var wakeOrder: [Int] { state.withLock { $0.wakeOrder } }

    /// Moves the clock forward and wakes the sleeps whose deadline is reached. A duration that is not positive moves
    /// nothing, so the time never goes back.
    public func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.offset += max(duration, .zero)
            let reached = state.waiters.filter { $0.deadline <= state.offset }
            state.waiters.removeAll { $0.deadline <= state.offset }
            let ordered = reached.sorted { ($0.deadline, $0.call) < ($1.deadline, $1.call) }
            state.wakeOrder += ordered.map(\.call)
            return ordered
        }
        for waiter in due { waiter.continuation.resume() }
    }

    /// Suspends until `total` sleeps have been suspended on this clock since it was created. It returns at once for
    /// sleeps that already happened, so a test that advances step by step passes the running total each time.
    public func waitForSleeps(_ total: Int) async {
        let gate = state.withLock { state -> Gate? in
            if state.suspended >= total { return nil }
            let gate = Gate()
            state.watchers.append((total, gate))
            return gate
        }
        await gate?.wait()
    }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let call = state.withLock { state in
            defer { state.calls += 1 }
            return state.calls
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // The check for a cancellation that came first and the registration share one lock section, and so
                // does the removal by `cancel`, so a cancellation is seen by one of them and a sleep never stays.
                let entry = state.withLock { state -> Entry in
                    if Task.isCancelled { return .cancelled }
                    if deadline.offset <= state.offset { return .due }
                    state.waiters.append(Waiter(call: call, deadline: deadline.offset, continuation: continuation))
                    state.suspended += 1
                    let ready = state.watchers.filter { $0.total <= state.suspended }
                    state.watchers.removeAll { $0.total <= state.suspended }
                    return .suspended(opening: ready.map(\.gate))
                }
                switch entry {
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .due: continuation.resume()
                case .suspended(let gates): for gate in gates { gate.open() }
                }
            }
        } onCancel: {
            cancel(call: call)
        }
    }

    private func cancel(call: Int) {
        let waiter = state.withLock { state -> Waiter? in
            guard let index = state.waiters.firstIndex(where: { $0.call == call }) else { return nil }
            return state.waiters.remove(at: index)
        }
        waiter?.continuation.resume(throwing: CancellationError())
    }
}
