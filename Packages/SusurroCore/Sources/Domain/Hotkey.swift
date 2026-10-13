/// A hotkey transition. `at` is a monotonic timestamp (time since an arbitrary origin); only differences matter.
public enum HotkeyEvent: Sendable, Equatable {
    case down(at: Duration)
    case up(at: Duration)
}

public protocol HotkeySource: Sendable {
    func events() -> AsyncStream<HotkeyEvent>
}
