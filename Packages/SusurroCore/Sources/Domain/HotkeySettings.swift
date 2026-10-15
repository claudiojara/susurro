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

    /// Whether a hotkey that is listened to is made only of modifier keys, so the app needs Input Monitoring: the
    /// dictation one always, the command one while command mode is on.
    public var hotkeysNeedInputMonitoring: Bool {
        hotkeyConfiguration(for: .dictate).needsInputMonitoring
            || (value(for: CommandSettings.enabled) && hotkeyConfiguration(for: .command).needsInputMonitoring)
    }

    /// The shortcuts of the app that a new hotkey for `role` must not repeat: the hotkeys of the other roles that are
    /// listened to (the dictation one always, the command one while command mode is on), in the order of the roles, then
    /// the paste last dictation shortcut when one is assigned. A hotkey that is not listened to takes no keys, so a
    /// clash with it is told only once it is turned on (`commandHotkeyClashes`).
    public func shortcutsInUse(except role: HotkeyRole) -> [HotkeyConfiguration] {
        var inUse = HotkeyRole.allCases.filter { $0 != role && isActive($0) }.map { hotkeyConfiguration(for: $0) }
        if let pasteLast = value(for: PasteLastSettings.combo) {
            inUse.append(HotkeyConfiguration(kind: .keyed, combo: pasteLast))
        }
        return inUse
    }

    /// Whether command mode is on and its hotkey repeats, or nests with, another shortcut of the app. It can happen when
    /// the hotkey was stored while command mode was off; the hotkey service then does not listen to it, and the card says
    /// so.
    public var commandHotkeyClashes: Bool {
        guard isActive(.command) else { return false }
        let command = hotkeyConfiguration(for: .command)
        let others = shortcutsInUse(except: .command)
        return others.contains(command) || others.contains(where: command.overlaps)
    }

    /// Whether the hotkey of a role is listened to.
    private func isActive(_ role: HotkeyRole) -> Bool {
        switch role {
        case .dictate: true
        case .command: value(for: CommandSettings.enabled)
        }
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
