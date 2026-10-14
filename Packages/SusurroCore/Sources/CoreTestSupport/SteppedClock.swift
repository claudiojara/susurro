import Synchronization

/// A clock for tests. It moves only when the code under test sleeps, by the time it sleeps, or when a test advances it.
/// A sleep returns at once. Like `Task.sleep`, it throws when its task has been cancelled.
///
/// Use it when the code under test should run through its sleeps without waiting and the test only reads which sleeps it
/// asked for (`sleeps`), which ran to their end (`completedSleeps`) and how far the time moved (`elapsed`), or hooks
/// into each sleep to stand in for what happens meanwhile. When the test must decide when a timer fires, use
/// `ManualClock`: its sleeps stay suspended until the test advances the clock.
public final class SteppedClock: Clock, Sendable {
    public typealias Instant = TestInstant

    /// Runs on the main actor each time a sleep ends, standing in for whatever happens meanwhile. It may throw.
    public typealias SleepHook = @MainActor (Duration) throws -> Void

    private struct State {
        var offset = Duration.zero
        var requested: [Duration] = []
        var completed: [Duration] = []
        var hook: SleepHook?
        var suspension: Suspension?
    }

    /// Holds the next sleep until `release` is opened, and opens `entered` when that sleep has begun.
    public struct Suspension: Sendable {
        public let entered = Gate()
        public let release = Gate()
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { Instant(offset: elapsed) }
    public var minimumResolution: Duration { .nanoseconds(1) }

    /// The time that has passed since the clock was created.
    public var elapsed: Duration { state.withLock { $0.offset } }
    /// Every sleep that was asked for, in order.
    public var sleeps: [Duration] { state.withLock { $0.requested } }
    /// The sleeps that ran to their end instead of being cancelled.
    public var completedSleeps: [Duration] { state.withLock { $0.completed } }

    public func setHook(_ hook: SleepHook?) { state.withLock { $0.hook = hook } }

    /// Makes the next sleep wait for the returned suspension to be released. A sleep that waits does not move the time.
    public func suspendNextSleep() -> Suspension {
        let suspension = Suspension()
        state.withLock { $0.suspension = suspension }
        return suspension
    }

    public func advance(by duration: Duration) { state.withLock { $0.offset += duration } }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let requested = state.withLock { state -> Duration in
            let requested = deadline.offset - state.offset
            state.requested.append(requested)
            return requested
        }
        if let suspension = state.withLock({ state -> Suspension? in
            defer { state.suspension = nil }
            return state.suspension
        }) {
            suspension.entered.open()
            await suspension.release.wait()
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
