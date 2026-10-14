/// The timers the activation machine asks for: the safety cap of a recording and the double-tap window. Each one is a
/// task that sleeps on the injected clock and reports back when it is over. There is at most one of each kind, and
/// scheduling a kind again replaces the earlier timer. A timer that was cancelled never reports, even when its sleep had
/// just ended: every firing carries the token of the timer that made it, and only the current token counts.
struct ActivationTimers {
    enum Kind: Hashable, Sendable {
        case cap
        case doubleTap
    }

    private var timers: [Kind: (token: Int, task: Task<Void, Never>)] = [:]
    private var nextToken = 0

    /// The timers that are running.
    var activeCount: Int { timers.count }

    /// Starts the timer of `kind`. `fire` gets the token once `duration` has passed on `clock`.
    mutating func schedule(
        _ kind: Kind, after duration: Duration, on clock: any Clock<Duration>,
        fire: @escaping @Sendable (Int) async -> Void
    ) {
        timers[kind]?.task.cancel()
        let token = nextToken
        nextToken += 1
        let task = Task {
            do { try await clock.sleep(for: duration) } catch { return }
            guard !Task.isCancelled else { return }
            await fire(token)
        }
        timers[kind] = (token, task)
    }

    mutating func cancel(_ kind: Kind) {
        timers.removeValue(forKey: kind)?.task.cancel()
    }

    mutating func cancelAll() {
        for timer in timers.values { timer.task.cancel() }
        timers = [:]
    }

    /// Whether a firing with this token is the one of the timer that is running. If it is, the timer is over.
    mutating func complete(_ kind: Kind, token: Int) -> Bool {
        guard timers[kind]?.token == token else { return false }
        timers[kind] = nil
        return true
    }
}
