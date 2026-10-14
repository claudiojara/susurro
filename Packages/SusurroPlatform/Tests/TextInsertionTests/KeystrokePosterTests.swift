import CoreGraphics
import Domain
import Testing

@testable import TextInsertion

@MainActor
@Suite("Keystroke poster", .timeLimit(.minutes(1)))
struct KeystrokePosterTests {
    /// The events the poster sent to the system, in order.
    private final class Posted {
        var events: [CGEvent] = []
    }

    private func poster(
        trusted: Bool = true,
        held: CGEventFlags = [],
        makeEvent: @escaping PasteChord.MakeEvent = PasteChord.privateSourceEvent,
        keyCode: CGKeyCode = PasteChord.ansiVKeyCode,
        into posted: Posted = Posted()
    ) -> CGEventKeystrokePoster {
        CGEventKeystrokePoster(
            isTrusted: { trusted },
            heldFlags: { held },
            post: { posted.events.append($0) },
            makeEvent: makeEvent,
            pasteKeyCode: { keyCode }
        )
    }

    @Test("the V key is the one the layout in use puts it on, so Dvorak differs from QWERTY")
    func keyCodeComesFromTheLayout() throws {
        let qwerty = Posted()
        let dvorak = Posted()

        try poster(keyCode: 9, into: qwerty).postPaste()
        try poster(keyCode: 47, into: dvorak).postPaste()

        let codes = { (posted: Posted) in posted.events.map { $0.getIntegerValueField(.keyboardEventKeycode) } }
        #expect(codes(qwerty) == [9, 9])
        #expect(codes(dvorak) == [47, 47])
    }

    @Test("the key is looked up for every paste, because the layout can change")
    func lookedUpEachTime() throws {
        var lookups = 0
        let sut = CGEventKeystrokePoster(
            isTrusted: { true }, heldFlags: { [] }, post: { _ in },
            pasteKeyCode: {
                lookups += 1
                return 9
            })

        try sut.postPaste()
        try sut.postPaste()

        #expect(lookups == 2)
    }

    @Test("a trusted process posts the V key down and up with only Command")
    func postsTheChord() throws {
        let posted = Posted()

        try poster(into: posted).postPaste()

        #expect(posted.events.map(\.type) == [.keyDown, .keyUp])
        #expect(
            posted.events.map { $0.getIntegerValueField(.keyboardEventKeycode) }
                == Array(repeating: Int64(PasteChord.ansiVKeyCode), count: 2)
        )
        for event in posted.events {
            #expect(event.flags.intersection(PasteChordTests.allModifiers) == [.maskCommand])
        }
    }

    @Test("the hotkey's modifiers, still held, do not reach the posted chord")
    func hotkeyModifiersDoNotLeak() throws {
        let posted = Posted()
        let sut = poster(
            held: PasteChordTests.hotkeyModifiers,
            makeEvent: PasteChordTests.eventsCarrying(PasteChordTests.hotkeyModifiers),
            into: posted
        )

        try sut.postPaste()

        #expect(posted.events.count == 2)
        for event in posted.events {
            #expect(event.flags.intersection(PasteChordTests.allModifiers) == [.maskCommand])
        }
    }

    @Test("without Accessibility nothing is posted and the error says why")
    func accessibilityMissing() {
        let posted = Posted()

        #expect(throws: KeystrokeError.accessibilityNotGranted) {
            try poster(trusted: false, into: posted).postPaste()
        }
        #expect(posted.events.isEmpty)
    }

    @Test("an event that cannot be created posts nothing, so no key is left down", arguments: [true, false])
    func nothingIsPostedHalfway(failingKeyDown: Bool) {
        let posted = Posted()
        let makeEvent: PasteChord.MakeEvent = { keyCode, keyDown in
            keyDown == failingKeyDown ? nil : PasteChord.privateSourceEvent(keyCode: keyCode, keyDown: keyDown)
        }

        #expect(throws: KeystrokeError.eventCreationFailed) {
            try poster(makeEvent: makeEvent, into: posted).postPaste()
        }
        #expect(posted.events.isEmpty)
    }

    @Test("modifiers are held while the hotkey's keys are down")
    func modifiersHeldFollowsTheKeyboard() {
        #expect(poster(held: PasteChordTests.hotkeyModifiers).modifiersHeld())
        #expect(!poster(held: []).modifiersHeld())
    }
}
