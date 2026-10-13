import CoreGraphics
import Domain

/// The Command+V key events that paste at the cursor, and the check for modifier keys that are still down.
enum PasteChord {
    typealias MakeEvent = (_ keyCode: CGKeyCode, _ keyDown: Bool) -> CGEvent?

    /// The V key on an ANSI layout. Other layouts put V elsewhere, which a later change resolves.
    static let ansiVKeyCode: CGKeyCode = 9

    /// A bit that macOS 26 sets in the flags of a new key event and in the HID state at rest. It was observed, not
    /// documented, and it is not a held key.
    static let alwaysSetFlag = CGEventFlags(rawValue: 0x2000_0000)

    /// The keys that change what a key press means. This is an allowlist: `alwaysSetFlag` is not in it, and neither are
    /// Caps Lock, which stays set while it is on, and Fn and the numeric pad, which flag arrow and function keys.
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
