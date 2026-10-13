import Synchronization

/// A `sleep` for tests: every sleep waits until the test calls `fire(_:)` for its duration, or until its task is
/// cancelled, in which case it throws like `Task.sleep`. The debounce and retry timing of the watcher is then decided
/// by the test, not by a clock.
///
/// It plays the part of `FakeSleeper` in CoreTestSupport, which this package does not depend on. Durations tell the
/// sleeps apart, so the code under test must use a different duration for each kind of wait.
final class ManualSleeper: Sendable {
    private struct Waiter {
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var waiters: [Int: Waiter] = [:]
        var nextID = 0
        var cancelled = 0
    }

    private let state = Mutex(State())

    /// How many sleeps of this duration are waiting now.
    func waiting(_ duration: Duration) -> Int {
        state.withLock { $0.waiters.values.filter { $0.duration == duration }.count }
    }

    /// How many sleeps ended by cancellation.
    var cancelled: Int { state.withLock { $0.cancelled } }

    /// Ends the sleeps of this duration that are waiting now. A sleep that begins later waits for the next call.
    func fire(_ duration: Duration) {
        let fired = state.withLock { state in
            let ids = state.waiters.filter { $0.value.duration == duration }.keys
            return ids.compactMap { state.waiters.removeValue(forKey: $0) }
        }
        for waiter in fired { waiter.continuation.resume() }
    }

    func sleep(_ duration: Duration) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // One critical section for the check and the registration, so a cancellation lands before or after.
                let alreadyCancelled = state.withLock { state in
                    if Task.isCancelled {
                        state.cancelled += 1
                        return true
                    }
                    state.waiters[id] = Waiter(duration: duration, continuation: continuation)
                    return false
                }
                if alreadyCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiter = state.withLock { state in
                let waiter = state.waiters.removeValue(forKey: id)
                if waiter != nil { state.cancelled += 1 }
                return waiter
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }
}

/// A count of calls that a test can read at once.
final class Counter: Sendable {
    private let value = Mutex(0)

    var count: Int { value.withLock { $0 } }

    func record() {
        value.withLock { $0 += 1 }
    }
}

/// Polls `condition` until it holds. The limit is long and only a failing run reaches it. Nothing is measured by this
/// wait: it only lets work that has no way to be awaited, such as a file system event, arrive.
func eventually(_ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

/// Gives tasks that are ready to run a chance to run, so a test can see that something that must not happen did not.
func letTasksRun() async {
    for _ in 0..<100 { await Task.yield() }
}
