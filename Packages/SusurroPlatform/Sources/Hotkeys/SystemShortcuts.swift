import Domain
import KeyboardShortcuts

/// The shortcuts that System Settings has turned on (Spotlight, Mission Control, the screenshots), which the system takes
/// before any app can.
public enum SystemShortcuts {
    /// Whether an enabled shortcut of the system already uses the combo. A combo without a key is taken by nothing.
    @MainActor
    public static func isTaken(_ combo: HotkeyCombo) -> Bool {
        KeyboardShortcuts.Shortcut(combo)?.isTakenBySystem ?? false
    }
}
