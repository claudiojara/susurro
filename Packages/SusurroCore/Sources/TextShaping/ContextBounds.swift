/// The text around the cursor, cut to what the pipeline may carry.
public struct BoundedFieldText: Sendable, Equatable {
    public let before: String
    public let after: String
    public let selection: String

    public static let empty = BoundedFieldText(before: "", after: "", selection: "")
}

/// Cuts the text of a field to the characters nearest the cursor. Lengths are counted in characters as the user sees
/// them (grapheme clusters), and a cut never falls inside one, so an emoji with a skin tone or an accent made of two
/// scalars is kept whole or left out.
public enum ContextBounds {
    /// The most characters kept before the cursor, and after it.
    public static let maxAroundCursor = 500
    /// The most characters kept of the selection.
    public static let maxSelection = 1_000

    /// - Parameters:
    ///   - fieldText: The whole text of the field.
    ///   - selection: The cursor or the selection in `fieldText`, in UTF-16 units, as the accessibility API gives it. A
    ///     cursor inside a character counts as before it. Without it the cursor is unknown, and nothing is kept
    ///     around it.
    ///   - selectedText: The selected text, for an app that gives it without the field.
    public static func bound(fieldText: String?, selection: Range<Int>?, selectedText: String?) -> BoundedFieldText {
        guard let text = fieldText, let selection else {
            return BoundedFieldText(before: "", after: "", selection: String((selectedText ?? "").prefix(maxSelection)))
        }
        let total = text.utf16.count
        let lower = min(max(selection.lowerBound, 0), total)
        let upper = min(max(selection.upperBound, lower), total)
        var (start, end) = boundaries(of: text, lower: lower, upper: upper)
        if lower == upper { end = start }
        return BoundedFieldText(
            before: String(text[..<start].suffix(maxAroundCursor)),
            after: String(text[end...].prefix(maxAroundCursor)),
            selection: String(text[start..<end].prefix(maxSelection)))
    }

    /// The character boundary at or before `lower` and the one at or after `upper`, found in one pass.
    private static func boundaries(of text: String, lower: Int, upper: Int) -> (String.Index, String.Index) {
        var start = text.startIndex
        var end = text.endIndex
        var endFound = false
        var offset = 0
        var index = text.startIndex
        while true {
            if offset <= lower { start = index }
            if !endFound && offset >= upper {
                end = index
                endFound = true
            }
            if index == text.endIndex || (offset > lower && endFound) { break }
            let next = text.index(after: index)
            offset += text.utf16.distance(from: index, to: next)
            index = next
        }
        return (start, end)
    }
}
