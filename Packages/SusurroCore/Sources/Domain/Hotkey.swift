/// What a hotkey is for. Each role has a hotkey of its own, and the presses of one never finish a press of the other.
public enum HotkeyRole: String, Sendable, Equatable, CaseIterable {
    /// Hold to dictate: the text goes in at the cursor.
    case dictate
    /// Hold to say an instruction that rewrites the selected text (command mode).
    case command
}

/// A hotkey transition. `at` is a monotonic timestamp (time since an arbitrary origin); only differences matter. `role`
/// says which hotkey it was.
public enum HotkeyEvent: Sendable, Equatable {
    case down(at: Duration, role: HotkeyRole = .dictate)
    case up(at: Duration, role: HotkeyRole = .dictate)
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
