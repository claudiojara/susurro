import AppKit
import KeyboardShortcuts

/// The one hotkey the app registers until it becomes configurable.
enum DefaultHotkey {
    /// Control+Option+D. It matches no enabled macOS shortcut (checked in ADR 0005). Re-run that check before changing
    /// it. A keyed combo needs no Input Monitoring.
    ///
    /// It is registered by value, so nothing is stored in UserDefaults: no earlier run can override it, and no write can
    /// re-register it while the key is held.
    static let holdToTalk = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option])
}
