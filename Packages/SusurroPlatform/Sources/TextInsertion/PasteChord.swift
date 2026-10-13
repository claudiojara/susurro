import CoreGraphics
import Domain

/// The Command+V key events that paste at the cursor, and the check for modifier keys that are still down.
enum PasteChord {
    typealias MakeEvent = (_ keyCode: CGKeyCode, _ keyDown: Bool) -> CGEvent?

    /// The V key on an ANSI layout. Other layouts put V elsewhere, which a later change resolves.
    static let ansiVKeyCode: CGKeyCode = 9

    /// The keys that change what a key press means. Caps Lock stays set while it is on, and Fn and the numeric pad
    /// flag arrow and function keys, so none of them says that a key is held.
    private static let heldKeyModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    /// The key-down and key-up events of the chord. Creating both comes first, so a failure posts nothing.
    static func events(
        keyCode: CGKeyCode = ansiVKeyCode,
        makeEvent: MakeEvent = privateSourceEvent
    ) throws -> [CGEvent] {
        try [true, false].map { keyDown in
            guard let event = makeEvent(keyCode, keyDown) else { throw KeystrokeError.eventCreationFailed }
            // An event can start with the flags of the keys the system sees held, such as the hotkey's Control and
            // Option. The flags are replaced, not added to, so only Command reaches the app.
            event.flags = .maskCommand
            return event
        }
    }

    /// An event from a source with its own key state, which starts with no modifiers held.
    static func privateSourceEvent(keyCode: CGKeyCode, keyDown: Bool) -> CGEvent? {
        CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: keyCode, keyDown: keyDown)
    }

    static func isModifierHeld(in flags: CGEventFlags) -> Bool {
        !flags.isDisjoint(with: heldKeyModifiers)
    }
}
