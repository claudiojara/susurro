import Domain
import KeyboardShortcuts

/// A hotkey written as key caps, such as `⌃` `⌥` `D`, for the settings to show.
public enum HotkeyKeyCaps {
    /// The modifiers of the hotkey in the order of the menus, with fn first, and then its key if it has one.
    @MainActor
    public static func caps(for configuration: HotkeyConfiguration) -> [String] {
        var caps = configuration.combo.modifiers.caps
        if let keyCode = configuration.combo.keyCode { caps.append(keyName(keyCode)) }
        return caps
    }

    /// The name of a key on the keyboard that is in use: its letter or digit, or its symbol (`↩`, `→`, `F5`, `Space`). A
    /// key the system has no name for is shown by its code.
    @MainActor
    public static func keyName(_ keyCode: Int) -> String {
        // A shortcut without modifiers prints the key alone. The system draws "�" for a code it cannot translate.
        let name = KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: 0).description
        return name.contains("\u{FFFD}") ? "Key \(keyCode)" : name
    }
}
