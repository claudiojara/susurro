/// Why a recorded hotkey is not accepted.
public enum HotkeyRejection: Sendable, Equatable, CaseIterable {
    /// A key with no modifier, or with Shift or Option or Command alone, would clash with typing or with the shortcuts of
    /// the apps. A key needs Control, or Option and Command together.
    case needsStrongerModifiers
    /// Escape cancels a dictation, so it cannot also start one.
    case escapeIsReserved
    /// fn cannot be held with a key: the system does not register such a shortcut.
    case functionNeedsToBeAlone
    /// A shortcut of System Settings (Spotlight, Mission Control, the screenshots) is on and would take the key first.
    case takenBySystem
    /// Hotkeys of modifier keys alone must be fn, or two or more modifier keys, since one is pressed all the time by
    /// accident.
    case needsFunctionOrTwoModifiers
    /// The shortcut that pastes the last dictation is tapped, so it needs a key, not modifier keys alone.
    case needsKey
    /// The dictation hotkey already uses the combo.
    case sameAsDictation
    /// Another hotkey of the app (dictation or command mode) is already this one.
    case alreadyInUse
    /// The modifier keys of a modifier-only hotkey are part of another hotkey of the app, or the other way round: pressing
    /// one passes through the other, which would start first.
    case overlapsAnotherHotkey
}

/// The rules a hotkey has to follow. A pure function, so that the settings and the tests share them.
public enum HotkeyValidation {
    /// Why `configuration` is not allowed, or nil when it is.
    /// - Parameters:
    ///   - isTakenBySystem: Whether an enabled shortcut of the system already uses the combo. It is asked only about a
    ///     keyed combo that passed every other rule.
    ///   - inUse: The hotkeys of the app's other roles. A hotkey equal to one of them, or whose modifier chord nests with
    ///     one of them (`HotkeyConfiguration.overlaps`), is refused once it passed the rules above.
    public static func rejection(
        of configuration: HotkeyConfiguration, isTakenBySystem: (HotkeyCombo) -> Bool,
        inUse: [HotkeyConfiguration] = []
    ) -> HotkeyRejection? {
        if let rejection = ruleRejection(of: configuration, isTakenBySystem: isTakenBySystem) { return rejection }
        if inUse.contains(configuration) { return .alreadyInUse }
        return inUse.contains(where: configuration.overlaps) ? .overlapsAnotherHotkey : nil
    }

    private static func ruleRejection(
        of configuration: HotkeyConfiguration, isTakenBySystem: (HotkeyCombo) -> Bool
    ) -> HotkeyRejection? {
        let combo = configuration.combo
        switch configuration.kind {
        case .modifierOnly:
            let isFunctionAlone = combo.modifiers == .function
            return isFunctionAlone || combo.modifiers.count >= 2 ? nil : .needsFunctionOrTwoModifiers
        case .keyed:
            if combo.keyCode == HotkeyKeyCodes.escape && combo.modifiers.isEmpty { return .escapeIsReserved }
            if combo.modifiers.contains(.function) { return .functionNeedsToBeAlone }
            let isFunctionKey = combo.keyCode.map(HotkeyKeyCodes.functionKeys.contains) ?? false
            let isStrong = combo.modifiers.contains(.control) || combo.modifiers.isSuperset(of: [.option, .command])
            if !isFunctionKey && !isStrong { return .needsStrongerModifiers }
            return isTakenBySystem(combo) ? .takenBySystem : nil
        }
    }
}

extension HotkeyConfiguration {
    /// Whether this hotkey and `other` cannot both be listened to: one of them is modifier-only and its modifiers are all
    /// held while the other is pressed. A modifier-only hotkey starts as soon as its exact modifiers are down, so it would
    /// fire on the way to the other one (Control+Option on the way to Control+Option+Shift, or to Control+Option+D).
    /// Two keyed hotkeys never overlap, and two equal hotkeys are a duplicate, not an overlap.
    public func overlaps(_ other: HotkeyConfiguration) -> Bool {
        guard self != other else { return false }
        let mine = combo.modifiers
        let theirs = other.combo.modifiers
        return (kind == .modifierOnly && theirs.isSuperset(of: mine))
            || (other.kind == .modifierOnly && mine.isSuperset(of: theirs))
    }
}
