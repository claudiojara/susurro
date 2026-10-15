import Domain
import Testing

@Suite("Hotkey validation")
struct HotkeyValidationTests {
    private static let d = 2
    private static let space = 49
    private static let escape = 53
    private static let f5 = 96

    private func keyed(_ code: Int, _ modifiers: HotkeyModifiers) -> HotkeyConfiguration {
        HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: code, modifiers: modifiers))
    }

    private func modifierOnly(_ modifiers: HotkeyModifiers) -> HotkeyConfiguration {
        HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: modifiers))
    }

    private func rejection(of configuration: HotkeyConfiguration, taken: Bool = false) -> HotkeyRejection? {
        HotkeyValidation.rejection(of: configuration, isTakenBySystem: { _ in taken })
    }

    @Test(
        "a key with Control, or with Option and Command, is accepted",
        arguments: [
            HotkeyModifiers.control, [.control, .option], [.control, .shift], [.option, .command],
            [.control, .command], [.control, .option, .command],
        ])
    func acceptedKeyed(modifiers: HotkeyModifiers) {
        #expect(rejection(of: keyed(Self.d, modifiers)) == nil)
    }

    @Test("the default hotkey is accepted")
    func defaultIsAccepted() {
        #expect(rejection(of: .standard) == nil)
    }

    @Test(
        "a key without Control, and without Option and Command together, would clash with typing or with apps",
        arguments: [
            HotkeyModifiers([]), .shift, .option, [.option, .shift], .command, [.command, .shift],
        ])
    func tooLightKeyed(modifiers: HotkeyModifiers) {
        #expect(rejection(of: keyed(Self.d, modifiers)) == .needsStrongerModifiers)
    }

    @Test("a function key needs no modifier")
    func functionKeys() {
        #expect(rejection(of: keyed(Self.f5, [])) == nil)
        #expect(rejection(of: keyed(Self.f5, .command)) == nil)
    }

    @Test("Escape is kept for cancelling a dictation")
    func escapeIsReserved() {
        #expect(rejection(of: keyed(Self.escape, [])) == .escapeIsReserved)
        #expect(rejection(of: keyed(Self.escape, .control)) == nil)
    }

    @Test("fn cannot be combined with a key")
    func functionWithKey() {
        #expect(rejection(of: keyed(Self.d, [.function, .control])) == .functionNeedsToBeAlone)
    }

    @Test("a shortcut that System Settings already uses is refused, after asking about the combo that was recorded")
    func takenBySystem() {
        var asked: [HotkeyCombo] = []
        let result = HotkeyValidation.rejection(
            of: keyed(Self.space, .control),
            isTakenBySystem: {
                asked.append($0)
                return true
            })

        #expect(result == .takenBySystem)
        #expect(asked == [HotkeyCombo(keyCode: Self.space, modifiers: .control)])
    }

    @Test("the system is not asked about a combo that was refused already")
    func systemIsAskedLast() {
        var asked = 0
        let result = HotkeyValidation.rejection(
            of: keyed(Self.d, .shift),
            isTakenBySystem: { _ in
                asked += 1
                return true
            })

        #expect(result == .needsStrongerModifiers)
        #expect(asked == 0)
    }

    @Test("fn alone, or two or more modifier keys, are accepted as a modifier-only hotkey")
    func acceptedModifierOnly() {
        #expect(rejection(of: modifierOnly(.function)) == nil)
        #expect(rejection(of: modifierOnly([.control, .option])) == nil)
        #expect(rejection(of: modifierOnly([.function, .control])) == nil)
        #expect(rejection(of: modifierOnly([.command, .shift, .option])) == nil)
    }

    @Test(
        "a single modifier key other than fn is pressed too often by accident, so it is refused",
        arguments: [HotkeyModifiers.control, .option, .shift, .command, []])
    func singleModifier(modifiers: HotkeyModifiers) {
        #expect(rejection(of: modifierOnly(modifiers)) == .needsFunctionOrTwoModifiers)
    }

    @Test("a modifier-only hotkey is never asked about the system shortcuts, which have a key")
    func modifierOnlySkipsTheSystem() {
        #expect(rejection(of: modifierOnly([.control, .option]), taken: true) == nil)
    }
}

@Suite("Hotkey validation across roles")
struct HotkeyDuplicateValidationTests {
    private func rejection(of configuration: HotkeyConfiguration, inUse: [HotkeyConfiguration]) -> HotkeyRejection? {
        HotkeyValidation.rejection(of: configuration, isTakenBySystem: { _ in false }, inUse: inUse)
    }

    @Test("a hotkey that another role already uses is refused")
    func duplicateIsRefused() {
        #expect(rejection(of: .standard, inUse: [.command, .standard]) == .alreadyInUse)
        #expect(rejection(of: .command, inUse: [.standard]) == nil)
    }

    @Test("a modifier-only chord equal to another role's is refused, and the same keys of another kind are not equal")
    func modifierOnlyDuplicate() {
        let chord = HotkeyConfiguration(
            kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: [.control, .option]))

        #expect(rejection(of: chord, inUse: [chord]) == .alreadyInUse)
        #expect(rejection(of: chord, inUse: [.command]) == .overlapsAnotherHotkey)
    }

    private static func modifierOnly(_ modifiers: HotkeyModifiers) -> HotkeyConfiguration {
        HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: modifiers))
    }

    @Test("a modifier-only chord whose keys are part of another role's hotkey is refused, either way round")
    func nestedModifierChords() {
        let controlOption = Self.modifierOnly([.control, .option])
        let controlOptionShift = Self.modifierOnly([.control, .option, .shift])

        // Pressing Control, Option, Shift in that order passes through Control+Option.
        #expect(rejection(of: controlOptionShift, inUse: [controlOption]) == .overlapsAnotherHotkey)
        #expect(rejection(of: controlOption, inUse: [controlOptionShift]) == .overlapsAnotherHotkey)
        // Control+Option alone would take the keys a keyed Control+Option+D starts with, and the other way round.
        #expect(rejection(of: controlOption, inUse: [.standard]) == .overlapsAnotherHotkey)
        #expect(rejection(of: .standard, inUse: [controlOption]) == .overlapsAnotherHotkey)
        #expect(rejection(of: .command, inUse: [controlOption]) == .overlapsAnotherHotkey)
    }

    @Test("chords that do not nest are allowed, and two keyed hotkeys never overlap")
    func disjointChords() {
        let controlOption = Self.modifierOnly([.control, .option])
        let function = Self.modifierOnly(.function)
        let commandOption = Self.modifierOnly([.command, .option])

        #expect(rejection(of: function, inUse: [.standard, .command, controlOption]) == nil)
        #expect(rejection(of: commandOption, inUse: [.standard, controlOption]) == nil)
        #expect(rejection(of: .command, inUse: [.standard]) == nil)
        #expect(Self.modifierOnly([.control, .shift]).overlaps(controlOption) == false)
    }

    @Test("the paste last shortcut cannot hold the keys of a modifier-only dictation hotkey")
    func pasteLastAgainstModifierOnlyDictation() {
        let pasteLast = HotkeyConfiguration(
            kind: .keyed, combo: HotkeyCombo(keyCode: 9, modifiers: [.control, .option]))

        #expect(
            PasteLastValidation.rejection(
                of: pasteLast, dictation: Self.modifierOnly([.control, .option]), isTakenBySystem: { _ in false })
                == .overlapsAnotherHotkey)
    }

    @Test("the paste last shortcut cannot take the command hotkey either")
    func pasteLastAgainstCommand() {
        #expect(
            PasteLastValidation.rejection(
                of: .command, dictation: .standard, isTakenBySystem: { _ in false }, inUse: [.command])
                == .alreadyInUse)
        #expect(
            PasteLastValidation.rejection(
                of: .standard, dictation: .standard, isTakenBySystem: { _ in false }, inUse: [.command])
                == .sameAsDictation)
    }

    @Test("a hotkey that breaks a rule says so before it is compared with the others")
    func rulesComeFirst() {
        let bare = HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: 2, modifiers: []))

        #expect(rejection(of: bare, inUse: [bare]) == .needsStrongerModifiers)
    }
}
