/// Lets input levels through no more often than the overlay can use them. A level that arrives sooner than `interval`
/// after the one that was let through is dropped; the next one that arrives after it is let through. Time is read from a
/// closure, so a test moves it by hand.
struct LevelThrottle {
    /// 30 updates a second, the most the specs allow. It is rounded up, so that a burst never gets a fourth update into
    /// 100 ms.
    static let standardInterval = Duration.nanoseconds(33_333_334)

    private let interval: Duration
    private let uptime: () -> Duration
    private var lastDelivery: Duration?

    /// - Parameter uptime: The time since an arbitrary origin; only differences matter.
    init(interval: Duration = Self.standardInterval, uptime: @escaping () -> Duration) {
        self.interval = interval
        self.uptime = uptime
    }

    /// The level to show now, or nil when it came too soon after the last one.
    mutating func accept(_ level: Double) -> Double? {
        let now = uptime()
        if let lastDelivery, now - lastDelivery < interval { return nil }
        lastDelivery = now
        return level
    }

    /// Forgets the last delivery, so that the first level of the next recording is shown at once.
    mutating func reset() {
        lastDelivery = nil
    }
}
