/// The shortcut that pastes the last dictation again, stored as `pasteLast.combo`. Unassigned by default: a global
/// shortcut takes its keys from every app, so the app does not take one the user did not ask for.
public enum PasteLastSettings {
    public static let combo = SettingKey<HotkeyCombo?>.json(area: "pasteLast", name: "combo", default: nil)

    public static let all: [any AnySettingKey] = [combo]
}

/// A value each time a shortcut is pressed. The live one listens to the shortcut in the settings; tests script presses.
public protocol ShortcutPressSource: Sendable {
    /// A new stream on each call, until it is no longer read.
    func presses() -> AsyncStream<Void>
}

/// The rules of the paste last dictation shortcut: those of every hotkey, a key to tap, not the dictation hotkey, and
/// none of the app's other hotkeys (`inUse`, such as the command one).
public enum PasteLastValidation {
    public static func rejection(
        of configuration: HotkeyConfiguration, dictation: HotkeyConfiguration,
        isTakenBySystem: (HotkeyCombo) -> Bool, inUse: [HotkeyConfiguration] = []
    ) -> HotkeyRejection? {
        guard configuration.kind == .keyed else { return .needsKey }
        if configuration == dictation { return .sameAsDictation }
        return HotkeyValidation.rejection(
            of: configuration, isTakenBySystem: isTakenBySystem, inUse: inUse + [dictation])
    }
}
