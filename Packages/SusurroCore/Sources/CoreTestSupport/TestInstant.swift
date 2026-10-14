/// A point in time on a test clock: how long after the clock was created. `ManualClock` and `SteppedClock` both use it,
/// so a test helper that takes an instant works with either.
public struct TestInstant: InstantProtocol, Sendable {
    /// The time since the clock was created.
    public let offset: Duration

    public init(offset: Duration) {
        self.offset = offset
    }

    public func advanced(by duration: Duration) -> TestInstant { TestInstant(offset: offset + duration) }
    public func duration(to other: TestInstant) -> Duration { other.offset - offset }
    public static func < (lhs: TestInstant, rhs: TestInstant) -> Bool { lhs.offset < rhs.offset }
}
