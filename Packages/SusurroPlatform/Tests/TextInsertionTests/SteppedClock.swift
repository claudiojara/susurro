import Synchronization

/// A clock for tests. It moves only when the code under test sleeps, by the time it sleeps, or when a test advances it.
/// A sleep returns at once. Like `Task.sleep`, it throws when its task has been cancelled.
final class SteppedClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    /// Runs on the main actor each time a sleep ends, standing in for whatever happens meanwhile. It may throw.
    typealias SleepHook = @MainActor (Duration) throws -> Void

    private struct State {
        var offset = Duration.zero
        var requested: [Duration] = []
        var completed: [Duration] = []
        var hook: SleepHook?
    }

    private let state = Mutex(State())

    var now: Instant { Instant(offset: elapsed) }
    var minimumResolution: Duration { .nanoseconds(1) }

    /// The time that has passed since the clock was created.
    var elapsed: Duration { state.withLock { $0.offset } }
    /// Every sleep that was asked for, in order.
    var sleeps: [Duration] { state.withLock { $0.requested } }
    /// The sleeps that ran to their end instead of being cancelled.
    var completedSleeps: [Duration] { state.withLock { $0.completed } }

    func setHook(_ hook: SleepHook?) { state.withLock { $0.hook = hook } }
    func advance(by duration: Duration) { state.withLock { $0.offset += duration } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let requested = state.withLock { state -> Duration in
            let requested = deadline.offset - state.offset
            state.requested.append(requested)
            return requested
        }
        try Task.checkCancellation()
        let hook = state.withLock { state -> SleepHook? in
            state.offset = max(state.offset, deadline.offset)
            state.completed.append(requested)
            return state.hook
        }
        if let hook { try await MainActor.run { try hook(requested) } }
    }
}
