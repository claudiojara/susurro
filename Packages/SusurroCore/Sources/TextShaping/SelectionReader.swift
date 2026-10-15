import Domain

/// What a command found selected in the focused element.
public enum SelectionCapture: Sendable, Equatable {
    /// The selected text, within `CommandLimits.maxSelection`.
    case text(String)
    /// Nothing is selected, or only blanks.
    case none
    /// The selection is longer than `CommandLimits.maxSelection`.
    case tooLong
    /// The focused element is a password field, which is never read.
    case secure
    /// Nothing could be read through Accessibility.
    case unreadable
}

/// Takes the selection out of what the accessibility API gave for the focused element: the selected text when the app
/// gives it, or else the selected range cut out of the field. A pure function, so the rules are tested without an app.
/// The selection lives in memory for its command only and is never stored or logged.
public enum SelectionReader {
    public static func capture(
        from snapshot: FocusedContext?, limit: Int = CommandLimits.maxSelection
    ) -> SelectionCapture {
        guard let snapshot else { return .unreadable }
        guard !snapshot.isSecure else { return .secure }
        let text = nonBlank(snapshot.selectedText) ?? nonBlank(slice(snapshot.fieldText, snapshot.selection))
        guard let text else { return .none }
        return text.count > limit ? .tooLong : .text(text)
    }

    /// Whether two readings of a selection are the same text, whatever their spacing. A selection that is gone is never
    /// the same as one that was there.
    public static func isSame(_ first: String, _ second: String) -> Bool {
        let folded = (spacingFolded(first), spacingFolded(second))
        return !folded.0.isEmpty && folded.0 == folded.1
    }

    private static func spacingFolded(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.allSatisfy(\.isWhitespace) else { return nil }
        return text
    }

    /// The part of the field in the range, counted in UTF-16 units as the accessibility API counts. Nil for a range that
    /// does not fit the field.
    private static func slice(_ field: String?, _ range: Range<Int>?) -> String? {
        guard let field, let range, !range.isEmpty, range.lowerBound >= 0 else { return nil }
        let units = field.utf16
        guard range.upperBound <= units.count,
            let start = units.index(units.startIndex, offsetBy: range.lowerBound, limitedBy: units.endIndex),
            let end = units.index(units.startIndex, offsetBy: range.upperBound, limitedBy: units.endIndex),
            let lower = start.samePosition(in: field), let upper = end.samePosition(in: field)
        else { return nil }
        return String(field[lower..<upper])
    }
}
