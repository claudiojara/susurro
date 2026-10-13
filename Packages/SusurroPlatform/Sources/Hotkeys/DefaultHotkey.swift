import AppKit
import KeyboardShortcuts

/// The one hotkey the app registers until it becomes configurable.
enum DefaultHotkey {
    /// Control+Option+D. It matches no enabled macOS shortcut (checked in ADR 0005). Re-run that check before changing
    /// it. A keyed combo needs no Input Monitoring.
    static var holdToTalk: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option])
    }
}

extension KeyboardShortcuts.Name {
    static var holdToTalk: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("holdToTalk", default: DefaultHotkey.holdToTalk)
    }
}
