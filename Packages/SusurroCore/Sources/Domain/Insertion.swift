/// Why the text was left on the clipboard instead of being pasted.
public enum ClipboardReason: Sendable, Equatable {
    case accessibilityMissing
    /// The paste did not happen for another reason, such as a modifier key that stayed down.
    case pasteFailed
}

public enum InsertionOutcome: Sendable, Equatable {
    case inserted
    case copiedToClipboard(ClipboardReason)
}

public enum KeystrokeError: Error, Sendable, Equatable {
    /// The system drops posted keystrokes from a process that is not trusted for Accessibility.
    case accessibilityNotGranted
    /// The system did not give a key event, so nothing was posted.
    case eventCreationFailed
}

/// Types the paste shortcut at the cursor of the frontmost app.
@MainActor
public protocol KeystrokePoster {
    /// Whether a modifier key is physically held, such as the hotkey's own keys still down after the release.
    func modifiersHeld() -> Bool
    /// Posts Command+V. Either both of its events are posted or none is.
    func postPaste() throws
}
