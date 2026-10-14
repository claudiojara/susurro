import Domain
import Foundation
import Synchronization

/// A date source that stays where the test put it.
public final class FakeDateSource: DateSource {
    private let current: Mutex<Date>

    public init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = Mutex(start)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func set(_ date: Date) {
        current.withLock { $0 = date }
    }

    public func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}
