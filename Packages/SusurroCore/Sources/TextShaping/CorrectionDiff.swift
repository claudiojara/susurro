/// One word, or a few, that the user typed over what a dictation wrote.
public struct WordCorrection: Sendable, Equatable {
    /// What the dictation wrote.
    public let heard: String
    /// What the user typed in its place, as the user spelled it.
    public let corrected: String

    public init(heard: String, corrected: String) {
        self.heard = heard
        self.corrected = corrected
    }
}

/// Finds the words the user corrected in the text of a dictation, from a later reading of the field. The dictation is
/// found again by the text that was around it when it was inserted, and its words are aligned with what is there now.
/// Only replacements of a few words count: added and removed words are the user writing on, not fixing a mishearing.
///
/// It is pure and works in memory: the field text it is given is dropped once it returns.
public enum CorrectionDiff {
    /// A field longer than this, in UTF-16 units, is not read.
    public static let maxFieldLength = 50_000
    /// The most words on either side of one correction.
    public static let maxCorrectionWords = 3
    /// The most words compared on either side, which keeps the alignment small.
    static let maxWords = 600

    /// The corrections in `fieldText`, or nil when the dictation could not be found in it (an anchor is gone, or the
    /// field is too big).
    ///
    /// - Parameters:
    ///   - inserted: The text the dictation inserted.
    ///   - anchorBefore: The text just before the dictation as it was inserted. Empty pins it to the start of the field.
    ///   - anchorAfter: The text just after it. Empty ends the region a little past the dictation's length.
    ///   - hint: Where the cursor is in `fieldText` now, in UTF-16 units: a text before that is found more than once is
    ///     taken nearest to it. Nil takes the first.
    public static func corrections(
        inserted: String, anchorBefore: String, anchorAfter: String, in fieldText: String, near hint: Int? = nil
    ) -> [WordCorrection]? {
        guard
            let region = region(
                insertedLength: inserted.utf16.count, before: anchorBefore, after: anchorAfter, in: fieldText,
                near: hint)
        else { return nil }
        let original = words(of: inserted)
        let edited = words(of: String(region))
        guard original.count <= maxWords, edited.count <= maxWords else { return nil }
        return replacements(original: original, edited: edited)
    }

    // MARK: Region

    private static func region(
        insertedLength: Int, before: String, after: String, in text: String, near hint: Int?
    ) -> Substring? {
        guard text.utf16.count <= maxFieldLength else { return nil }
        let start: String.Index
        if before.isEmpty {
            start = text.startIndex
        } else {
            let found = text.ranges(of: before)
            guard let first = found.first else { return nil }
            if let hint {
                // The cursor is past the dictation, so the anchor ends about the dictation's length before it.
                let target = hint - insertedLength
                start =
                    found.min {
                        abs(text.utf16.distance(from: text.startIndex, to: $0.upperBound) - target)
                            < abs(text.utf16.distance(from: text.startIndex, to: $1.upperBound) - target)
                    }?.upperBound ?? first.upperBound
            } else {
                start = first.upperBound
            }
        }
        let end: String.Index
        if after.isEmpty {
            end = text.utf16.index(start, offsetBy: insertedLength * 2 + 200, limitedBy: text.endIndex) ?? text.endIndex
        } else {
            guard let found = text[start...].range(of: after) else { return nil }
            end = found.lowerBound
        }
        return text[start..<end]
    }

    // MARK: Words

    /// A word as written, and the form it is compared by: lowercase, one kind of apostrophe. Accents count, so a
    /// correction of accents only is one.
    private struct Word {
        let text: String
        let key: String
    }

    /// The words of a text, split on white space, with the punctuation around each one dropped.
    private static func words(of text: String) -> [Word] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let trimmed = token.trimmingPrefix(while: { !isKept($0) })
            let word = String(trimmed.reversed().trimmingPrefix(while: { !isKept($0) }).reversed())
            guard !word.isEmpty else { return nil }
            let key = word.lowercased().replacing("’", with: "'").replacing("‘", with: "'")
            return Word(text: word, key: key)
        }
    }

    private static func isKept(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    // MARK: Alignment

    /// The runs of words that replace one another between the matched words of a longest common subsequence.
    private static func replacements(original: [Word], edited: [Word]) -> [WordCorrection] {
        let n = original.count
        let m = edited.count
        // lengths[i][j]: the longest common subsequence of original[i...] and edited[j...].
        var lengths = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lengths[i][j] =
                    original[i].key == edited[j].key
                    ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var result: [WordCorrection] = []
        var removed: [Word] = []
        var added: [Word] = []
        func flush() {
            if (1...maxCorrectionWords).contains(removed.count), (1...maxCorrectionWords).contains(added.count) {
                result.append(
                    WordCorrection(
                        heard: removed.map(\.text).joined(separator: " "),
                        corrected: added.map(\.text).joined(separator: " ")))
            }
            removed = []
            added = []
        }
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n, j < m, original[i].key == edited[j].key {
                flush()
                i += 1
                j += 1
            } else if j < m, i == n || lengths[i][j + 1] >= lengths[i + 1][j] {
                added.append(edited[j])
                j += 1
            } else {
                removed.append(original[i])
                i += 1
            }
        }
        flush()
        return result
    }
}
