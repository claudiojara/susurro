import ApplicationServices
import Domain

/// Posts Command+V to the user session as if it were typed. The system drops posted keystrokes unless the process is
/// trusted for Accessibility. The key is the one that types "v" on the layout in use, so the shortcut pastes on Dvorak
/// and other layouts too.
@MainActor
public final class CGEventKeystrokePoster: KeystrokePoster {
    private let isTrusted: () -> Bool
    private let heldFlags: () -> CGEventFlags
    private let post: (CGEvent) -> Void
    private let makeEvent: PasteChord.MakeEvent
    private let pasteKeyCode: () -> CGKeyCode

    public convenience init() {
        self.init(
            isTrusted: { AXIsProcessTrusted() },
            // The HID state is the physical keyboard. The session state also reflects events that apps post.
            heldFlags: { CGEventSource.flagsState(.hidSystemState) },
            // The session tap is above the HID stage, so the flags set on the event are not combined with the keyboard's
            // state there. The manual check against a real app confirms it.
            post: { $0.post(tap: .cgSessionEventTap) }
        )
    }

    init(
        isTrusted: @escaping () -> Bool,
        heldFlags: @escaping () -> CGEventFlags,
        post: @escaping (CGEvent) -> Void,
        makeEvent: @escaping PasteChord.MakeEvent = PasteChord.privateSourceEvent,
        pasteKeyCode: @escaping () -> CGKeyCode = { KeyLayout.pasteKeyCode() }
    ) {
        self.isTrusted = isTrusted
        self.heldFlags = heldFlags
        self.post = post
        self.makeEvent = makeEvent
        self.pasteKeyCode = pasteKeyCode
    }

    public func modifiersHeld() -> Bool {
        PasteChord.isModifierHeld(in: heldFlags())
    }

    public func postPaste() throws {
        guard isTrusted() else { throw KeystrokeError.accessibilityNotGranted }
        // The layout can change at any time, so the key is looked up for every paste.
        for event in try PasteChord.events(keyCode: pasteKeyCode(), makeEvent: makeEvent) {
            post(event)
        }
    }
}
