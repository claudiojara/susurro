/// The settings of the hotkey, stored as `hotkey.kind` and `hotkey.combo`. Nothing is stored until the user chooses a
/// hotkey, so the default can still change for everyone who never did.
public enum HotkeySettings {
    public static let kind = SettingKey<HotkeyKind>(area: "hotkey", name: "kind", default: .keyed)
    public static let combo = SettingKey<HotkeyCombo>.json(area: "hotkey", name: "combo", default: .holdToTalk)

    public static let all: [any AnySettingKey] = [kind, combo]
}

extension SettingsStore {
    /// The hotkey the user configured, or the default.
    public func hotkeyConfiguration() -> HotkeyConfiguration {
        HotkeyConfiguration(kind: value(for: HotkeySettings.kind), combo: value(for: HotkeySettings.combo))
    }

    /// Stores a hotkey. The hotkey service follows both keys and reads the pair each time, so for the moment between the two
    /// writes it may see the new combo with the old kind; the kind goes last so that the pair is whole after it.
    public func setHotkey(_ configuration: HotkeyConfiguration) {
        set(configuration.combo, for: HotkeySettings.combo)
        set(configuration.kind, for: HotkeySettings.kind)
    }
}
