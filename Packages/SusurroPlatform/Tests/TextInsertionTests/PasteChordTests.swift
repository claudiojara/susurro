import CoreGraphics
import Domain
import Testing

@testable import TextInsertion

@Suite("Paste chord", .timeLimit(.minutes(1)))
struct PasteChordTests {
    /// Every modifier a key event can carry.
    static let allModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskAlphaShift, .maskHelp,
        .maskNumericPad,
    ]

    /// Control and Option are the hotkey's modifiers.
    static let hotkeyModifiers: CGEventFlags = [.maskControl, .maskAlternate]

    /// An event source that mirrors the keys the user is holding, as the combined session state does.
    static func eventsCarrying(_ held: CGEventFlags) -> PasteChord.MakeEvent {
        { keyCode, keyDown in
            let event = CGEvent(
                keyboardEventSource: CGEventSource(stateID: .privateState),
                virtualKey: keyCode,
                keyDown: keyDown
            )
            event?.flags = held
            return event
        }
    }

    @Test("the chord is the V key going down and then up")
    func keyDownThenKeyUp() throws {
        let events = try PasteChord.events()

        #expect(events.map(\.type) == [.keyDown, .keyUp])
        #expect(
            events.map { $0.getIntegerValueField(.keyboardEventKeycode) }
                == Array(repeating: Int64(PasteChord.ansiVKeyCode), count: 2))
    }

    @Test("the key code is the one given", arguments: [0, 9, 40])
    func keyCodeIsTheOneGiven(keyCode: CGKeyCode) throws {
        let events = try PasteChord.events(keyCode: keyCode)

        #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [Int64(keyCode), Int64(keyCode)])
    }

    @Test("both events carry only the Command modifier")
    func onlyCommand() throws {
        let events = try PasteChord.events()

        #expect(events.count == 2)
        for event in events {
            #expect(event.flags.intersection(Self.allModifiers) == [.maskCommand])
        }
    }

    @Test(
        "modifiers the user is holding do not reach the chord",
        arguments: [
            Self.hotkeyModifiers,
            [.maskAlternate],
            [.maskShift],
            [.maskControl, .maskAlternate, .maskShift, .maskSecondaryFn],
            [.maskControl, .maskAlternate, .maskCommand],
        ] as [CGEventFlags]
    )
    func heldModifiersDoNotLeak(held: CGEventFlags) throws {
        let events = try PasteChord.events(makeEvent: Self.eventsCarrying(held))

        #expect(events.count == 2)
        for event in events {
            #expect(event.flags.intersection(Self.allModifiers) == [.maskCommand])
        }
    }

    @Test("an event that cannot be created fails the whole chord", arguments: [true, false])
    func eventCreationFailure(failingKeyDown: Bool) {
        let makeEvent: PasteChord.MakeEvent = { keyCode, keyDown in
            keyDown == failingKeyDown ? nil : Self.eventsCarrying([])(keyCode, keyDown)
        }

        #expect(throws: KeystrokeError.eventCreationFailed) {
            try PasteChord.events(makeEvent: makeEvent)
        }
    }

    @Test(
        "any of the four modifier keys counts as held",
        arguments: [
            CGEventFlags.maskControl, .maskAlternate, .maskShift, .maskCommand, Self.hotkeyModifiers,
        ]
    )
    func modifierHeld(flags: CGEventFlags) {
        #expect(PasteChord.isModifierHeld(in: flags))
    }

    @Test(
        "bits that are not held keys do not count",
        arguments: [
            // Caps Lock stays set while it is on, and Fn and the numeric pad flag arrow keys.
            CGEventFlags.maskAlphaShift, .maskSecondaryFn, .maskNumericPad,
            // The state at rest on macOS 26 already carries this bit.
            PasteChord.alwaysSetFlag,
            [],
        ]
    )
    func notAHeldKey(flags: CGEventFlags) {
        #expect(!PasteChord.isModifierHeld(in: flags))
    }

    @Test("a held modifier is found among bits that are not held keys")
    func heldAmongOtherBits() {
        let flags = PasteChord.alwaysSetFlag.union(Self.hotkeyModifiers)

        #expect(PasteChord.isModifierHeld(in: flags))
    }
}
