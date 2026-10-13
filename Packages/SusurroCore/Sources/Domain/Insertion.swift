/// Why the text was left on the clipboard instead of being pasted.
public enum ClipboardReason: Sendable, Equatable {
    case accessibilityMissing
}

public enum InsertionOutcome: Sendable, Equatable {
    case inserted
    case copiedToClipboard(ClipboardReason)
}
