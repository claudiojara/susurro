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
}

/// The rules a hotkey has to follow. A pure function, so that the settings and the tests share them.
public enum HotkeyValidation {
    /// Why `configuration` is not allowed, or nil when it is.
    /// - Parameters:
    ///   - isTakenBySystem: Whether an enabled shortcut of the system already uses the combo. It is asked only about a
    ///     keyed combo that passed every other rule.
    ///   - inUse: The hotkeys of the app's other roles. A hotkey equal to one of them is refused, once it passed the
    ///     rules above.
    public static func rejection(
        of configuration: HotkeyConfiguration, isTakenBySystem: (HotkeyCombo) -> Bool,
        inUse: [HotkeyConfiguration] = []
    ) -> HotkeyRejection? {
        if let rejection = ruleRejection(of: configuration, isTakenBySystem: isTakenBySystem) { return rejection }
        return inUse.contains(configuration) ? .alreadyInUse : nil
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
