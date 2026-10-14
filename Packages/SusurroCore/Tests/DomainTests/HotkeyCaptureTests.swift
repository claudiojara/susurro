import Domain
import Testing

@Suite("Hotkey capture")
struct HotkeyCaptureTests {
    private static let d = 2
    private static let escape = 53
    private static let rightArrow = 124
    private static let f5 = 96

    private func keyed(_ code: Int, _ modifiers: HotkeyModifiers = []) -> HotkeyCapture.Outcome {
        .candidate(HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: code, modifiers: modifiers)))
    }

    private func modifierOnly(_ modifiers: HotkeyModifiers) -> HotkeyCapture.Outcome {
        .candidate(HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: modifiers)))
    }

    /// Feeds the inputs one by one and returns what each of them gave.
    private func outcomes(_ inputs: [HotkeyCaptureInput]) -> [HotkeyCapture.Outcome] {
        var capture = HotkeyCapture()
        return inputs.map { capture.handle($0) }
    }

    @Test("a key pressed with modifiers is a keyed candidate at once")
    func keyedCandidate() {
        let result = outcomes([.key(code: Self.d, modifiers: [.control, .option])])

        #expect(result == [keyed(Self.d, [.control, .option])])
    }

    @Test("Escape alone cancels, and with a modifier it is a key like any other")
    func escape() {
        #expect(outcomes([.key(code: Self.escape, modifiers: [])]) == [.cancel])
        #expect(outcomes([.key(code: Self.escape, modifiers: .command)]) == [keyed(Self.escape, .command)])
    }

    @Test("fn alone is a modifier-only candidate when it is let go, and not before")
    func fnAlone() {
        let result = outcomes([.modifiers(.function), .modifiers([])])

        #expect(result == [.none, modifierOnly(.function)])
    }

    @Test("a chord of modifiers is the biggest set that was held, given when the last key is let go")
    func chord() {
        let result = outcomes([
            .modifiers(.control), .modifiers([.control, .option]), .modifiers(.option), .modifiers([]),
        ])

        #expect(result == [.none, .none, .none, modifierOnly([.control, .option])])
    }

    @Test("modifiers held and then a key make a keyed candidate, and letting the modifiers go adds nothing")
    func keyAfterModifiers() {
        let result = outcomes([
            .modifiers(.command), .key(code: Self.d, modifiers: .command), .modifiers([]),
        ])

        #expect(result == [.none, keyed(Self.d, .command), .none])
    }

    @Test("a new hold after a candidate starts from nothing")
    func secondHold() {
        let result = outcomes([
            .key(code: Self.d, modifiers: .command), .modifiers([]),
            .modifiers(.function), .modifiers([]),
        ])

        #expect(result == [keyed(Self.d, .command), .none, .none, modifierOnly(.function)])
    }

    @Test("the fn flag that the system adds to arrows and function keys is not part of the hotkey")
    func synthesizedFunctionFlag() {
        let result = outcomes([
            .key(code: Self.rightArrow, modifiers: [.function, .control]),
            .key(code: Self.f5, modifiers: .function),
        ])

        #expect(result == [keyed(Self.rightArrow, .control), keyed(Self.f5)])
    }

    @Test("fn held with an ordinary key stays in the combo, for the validation to refuse")
    func functionWithOrdinaryKey() {
        let result = outcomes([.key(code: Self.d, modifiers: [.function, .control])])

        #expect(result == [keyed(Self.d, [.function, .control])])
    }

    @Test("the modifiers held now are what a view shows while the user records")
    func heldModifiers() {
        var capture = HotkeyCapture()
        #expect(capture.held.isEmpty)

        _ = capture.handle(.modifiers([.control, .shift]))
        #expect(capture.held == [.control, .shift])

        _ = capture.handle(.modifiers(.control))
        #expect(capture.held == .control)

        _ = capture.handle(.modifiers([]))
        #expect(capture.held.isEmpty)
    }

    @Test("the key caps of the modifiers come in the order of the menu bar: fn, control, option, shift, command")
    func caps() {
        #expect(HotkeyModifiers([.command, .shift, .option, .control, .function]).caps == ["fn", "⌃", "⌥", "⇧", "⌘"])
        #expect(HotkeyModifiers([]).caps.isEmpty)
        #expect(HotkeyModifiers.function.caps == ["fn"])
    }
}
