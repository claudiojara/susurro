import ApplicationServices
import Domain

/// Posts Command+V to the user session as if it were typed. The system drops posted keystrokes unless the process is
/// trusted for Accessibility.
@MainActor
public final class CGEventKeystrokePoster: KeystrokePoster {
    private let isTrusted: () -> Bool
    private let heldFlags: () -> CGEventFlags
    private let post: (CGEvent) -> Void
    private let makeEvent: PasteChord.MakeEvent

    public convenience init() {
        self.init(
            isTrusted: { AXIsProcessTrusted() },
            // The HID state is the physical keyboard. The session state also reflects events that apps post.
            heldFlags: { CGEventSource.flagsState(.hidSystemState) },
            post: { $0.post(tap: .cgSessionEventTap) },
            makeEvent: PasteChord.privateSourceEvent
        )
    }

    init(
        isTrusted: @escaping () -> Bool,
        heldFlags: @escaping () -> CGEventFlags,
        post: @escaping (CGEvent) -> Void,
        makeEvent: @escaping PasteChord.MakeEvent
    ) {
        self.isTrusted = isTrusted
        self.heldFlags = heldFlags
        self.post = post
        self.makeEvent = makeEvent
    }

    public func modifiersHeld() -> Bool {
        PasteChord.isModifierHeld(in: heldFlags())
    }

    public func postPaste() throws {
        guard isTrusted() else { throw KeystrokeError.accessibilityNotGranted }
        for event in try PasteChord.events(makeEvent: makeEvent) {
            post(event)
        }
    }
}
