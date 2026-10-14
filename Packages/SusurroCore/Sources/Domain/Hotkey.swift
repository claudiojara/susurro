/// A hotkey transition. `at` is a monotonic timestamp (time since an arbitrary origin); only differences matter.
public enum HotkeyEvent: Sendable, Equatable {
    case down(at: Duration)
    case up(at: Duration)
    /// Escape was pressed. The source delivers it only while Esc is armed (`HotkeySource.setEscapeArmed`), so it never
    /// reaches the coordinator, and never gets swallowed from other apps, while nothing is in flight.
    case escape
}

public protocol HotkeySource: Sendable {
    func events() -> AsyncStream<HotkeyEvent>
    /// Registers the Escape handler while `armed` is true and unregisters it when false, so that Escape passes through to
    /// the frontmost app unless a dictation is in flight. Calling it again with the same value changes nothing.
    func setEscapeArmed(_ armed: Bool)
}
