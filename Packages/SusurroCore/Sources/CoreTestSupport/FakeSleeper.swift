import Synchronization

/// A `sleep` for tests. A pause (under a second) returns at once and is counted. A deadline whose duration is in
/// `expiring` also returns at once. Every other deadline waits until its task is cancelled, so it never fires.
public final class FakeSleeper: Sendable {
    private let expiring: Set<Duration>
    private let pauses = Mutex(0)

    public init(expiring: Set<Duration> = []) {
        self.expiring = expiring
    }

    public var pauseCount: Int { pauses.withLock { $0 } }

    public func sleep(_ duration: Duration) async throws {
        if duration < .seconds(1) {
            pauses.withLock { $0 += 1 }
        } else if !expiring.contains(duration) {
            await Gate().wait()
            try Task.checkCancellation()
        }
    }
}
