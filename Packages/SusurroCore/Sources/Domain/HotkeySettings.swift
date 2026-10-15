/// The settings of the hotkeys, stored as `hotkey.kind` and `hotkey.combo` for dictation and `hotkey.commandKind` and
/// `hotkey.commandCombo` for command mode. Nothing is stored until the user chooses a hotkey, so the default can still
/// change for everyone who never did.
public enum HotkeySettings {
    public static let kind = SettingKey<HotkeyKind>(area: "hotkey", name: "kind", default: .keyed)
    public static let combo = SettingKey<HotkeyCombo>.json(area: "hotkey", name: "combo", default: .holdToTalk)
    public static let commandKind = SettingKey<HotkeyKind>(area: "hotkey", name: "commandKind", default: .keyed)
    public static let commandCombo = SettingKey<HotkeyCombo>.json(
        area: "hotkey", name: "commandCombo", default: .holdToCommand)

    public static let all: [any AnySettingKey] = [kind, combo, commandKind, commandCombo]

    /// The two keys that hold the hotkey of a role.
    static func keys(for role: HotkeyRole) -> (kind: SettingKey<HotkeyKind>, combo: SettingKey<HotkeyCombo>) {
        switch role {
        case .dictate: (kind, combo)
        case .command: (commandKind, commandCombo)
        }
    }
}

extension HotkeyConfiguration {
    /// The hotkey a role has until the user chooses one.
    public static func defaultHotkey(for role: HotkeyRole) -> HotkeyConfiguration {
        switch role {
        case .dictate: .standard
        case .command: .command
        }
    }
}

extension SettingsStore {
    /// The dictation hotkey the user configured, or the default.
    public func hotkeyConfiguration() -> HotkeyConfiguration {
        hotkeyConfiguration(for: .dictate)
    }

    /// The hotkey of a role as the user configured it, or its default.
    public func hotkeyConfiguration(for role: HotkeyRole) -> HotkeyConfiguration {
        let keys = HotkeySettings.keys(for: role)
        return HotkeyConfiguration(kind: value(for: keys.kind), combo: value(for: keys.combo))
    }

    /// The shortcuts of the app that a new hotkey for `role` must not repeat: the hotkeys of the other roles, in the order
    /// of the roles, then the paste last dictation shortcut when one is assigned.
    public func shortcutsInUse(except role: HotkeyRole) -> [HotkeyConfiguration] {
        var inUse = HotkeyRole.allCases.filter { $0 != role }.map { hotkeyConfiguration(for: $0) }
        if let pasteLast = value(for: PasteLastSettings.combo) {
            inUse.append(HotkeyConfiguration(kind: .keyed, combo: pasteLast))
        }
        return inUse
    }

    /// Stores the dictation hotkey.
    public func setHotkey(_ configuration: HotkeyConfiguration) {
        setHotkey(configuration, for: .dictate)
    }

    /// Stores a hotkey. The hotkey service follows both keys and reads the pair each time, so for the moment between the two
    /// writes it may see the new combo with the old kind; the kind goes last so that the pair is whole after it.
    public func setHotkey(_ configuration: HotkeyConfiguration, for role: HotkeyRole) {
        let keys = HotkeySettings.keys(for: role)
        set(configuration.combo, for: keys.combo)
        set(configuration.kind, for: keys.kind)
    }

    /// Goes back to the default dictation hotkey.
    public func resetHotkey() {
        resetHotkey(for: .dictate)
    }

    /// Goes back to the default hotkey of a role by removing what the user chose, not by storing the default: nothing is
    /// stored until the user chooses, so the default can still change for everyone who never did.
    public func resetHotkey(for role: HotkeyRole) {
        let keys = HotkeySettings.keys(for: role)
        remove(keys.combo)
        remove(keys.kind)
    }
}
