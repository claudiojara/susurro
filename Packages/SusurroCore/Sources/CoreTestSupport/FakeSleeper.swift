import Synchronization

/// A `sleep` for code that takes a `sleep` closure and not a `Clock` (the coordinator and its limits); for code that
/// takes a clock, use `ManualClock` or `SteppedClock`. A pause (under a second) returns at once and is counted. A deadline whose duration is in
/// `expiring` also returns at once. Every other deadline waits until its task is cancelled, so it never fires, unless
/// the test calls `fire(_:)` for its duration. A sleeper that `blocksPauses` makes pauses wait too, which holds a
/// polling loop in place. A test that needs to know the code under test has reached a deadline waits on `entered(_:)`.
///
/// Deadlines are told apart by their duration, so two deadlines of one duration cannot be fired apart: give every limit
/// the code under test waits on a duration of its own.
public final class FakeSleeper: Sendable {
    private struct State {
        var pauses = 0
        var fired: Set<Duration> = []
        var waiting: [Duration: [Gate]] = [:]
        var entered: [Duration: Gate] = [:]
    }

    private let expiring: Set<Duration>
    private let blocksPauses: Bool
    private let state = Mutex(State())

    public init(expiring: Set<Duration> = [], blocksPauses: Bool = false) {
        self.expiring = expiring
        self.blocksPauses = blocksPauses
    }

    public var pauseCount: Int { state.withLock { $0.pauses } }

    /// A gate that opens when a sleep of this duration begins. An open made before the test asks is remembered.
    public func entered(_ duration: Duration) -> Gate {
        state.withLock { state in
            if let gate = state.entered[duration] { return gate }
            let gate = Gate()
            state.entered[duration] = gate
            return gate
        }
    }

    /// Ends the sleeps of this duration that are waiting, and every later one. A test calls it once the code under test
    /// has reached the point where the deadline should run out.
    public func fire(_ duration: Duration) {
        let gates = state.withLock { state in
            state.fired.insert(duration)
            return state.waiting.removeValue(forKey: duration) ?? []
        }
        for gate in gates { gate.open() }
    }

    public func sleep(_ duration: Duration) async throws {
        let isPause = duration < .seconds(1)
        if isPause { state.withLock { $0.pauses += 1 } }
        entered(duration).open()
        if isPause ? !blocksPauses : expiring.contains(duration) { return }
        let gate = Gate()
        let hasFired = state.withLock { state in
            if state.fired.contains(duration) { return true }
            state.waiting[duration, default: []].append(gate)
            return false
        }
        if hasFired { return }
        await gate.wait()
        // The gate opens when `fire` ends the sleep, and also when the task is cancelled. Like `Task.sleep`, a sleep
        // whose task was cancelled throws, whatever ended the wait.
        try Task.checkCancellation()
    }
}
