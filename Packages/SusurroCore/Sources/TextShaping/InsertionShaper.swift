import Domain
import Foundation

/// Adjusts the final text to the field it goes into, from the text around the cursor: the space before it, the case of
/// its first letter, a period that the following text already has, and the space after it. It is deterministic, applies
/// to every tone, and leaves the text alone when the surroundings are unknown.
public enum InsertionShaper {
    /// - Parameters:
    ///   - text: The final text: the cleaned transcript or the raw one.
    ///   - cursor: The text around the cursor, or nil when it could not be read.
    ///   - vocabulary: Terms whose capitalization is kept wherever they appear.
    public static func shape(_ text: String, around cursor: CursorContext?, vocabulary: [String]) -> String {
        guard let cursor else { return text }
        var shaped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shaped.isEmpty else { return text }
        shaped = adjustCase(of: shaped, before: cursor.before, vocabulary: vocabulary)
        shaped = dropRepeatedPeriod(from: shaped, after: cursor.after)
        let leading = needsLeadingSpace(before: cursor.before, text: shaped) ? " " : ""
        let trailing = cursor.after.first.map(TextCharacters.isWordCharacter) == true ? " " : ""
        return leading + shaped + trailing
    }

    // MARK: Leading space

    private static func needsLeadingSpace(before: String, text: String) -> Bool {
        guard let last = before.last, !last.isWhitespace, let first = text.first else { return false }
        return !TextCharacters.isClosingPunctuation(first)
    }

    // MARK: Case

    /// Whether the text starts a sentence: the field is empty, or the text before the cursor ends with a line break or
    /// a sentence terminator, each optionally followed by spaces.
    private static func startsSentence(after before: String) -> Bool {
        let trimmed = before.trimmingTrailing(" \t")
        guard let last = trimmed.last else { return true }
        return last.isNewline || TextCharacters.isSentenceTerminator(last)
    }

    private static func adjustCase(of text: String, before: String, vocabulary: [String]) -> String {
        guard let letterIndex = text.firstIndex(where: \.isLetter) else { return text }
        let letter = text[letterIndex]
        if startsSentence(after: before) {
            guard letter.isLowercase else { return text }
            return replacing(letterAt: letterIndex, in: text, with: letter.uppercased())
        }
        guard letter.isUppercase else { return text }
        let word = wordStarting(at: letterIndex, in: text)
        guard isOrdinaryCapitalizedWord(word), !isPronounI(word), !isVocabularyTerm(word, in: vocabulary) else {
            return text
        }
        return replacing(letterAt: letterIndex, in: text, with: letter.lowercased())
    }

    private static func wordStarting(at index: String.Index, in text: String) -> String {
        var end = index
        while end < text.endIndex, isWordPart(text[end]) { end = text.index(after: end) }
        return String(text[index..<end])
    }

    /// A letter, a digit, or an apostrophe inside a word.
    private static func isWordPart(_ character: Character) -> Bool {
        TextCharacters.isWordCharacter(character) || character == "'" || character == "’"
    }

    /// A word written with a capital first letter and nothing else in capitals ("Report"). Acronyms ("NASA") and words
    /// with a capital inside ("McDonald") are not, and keep their case.
    private static func isOrdinaryCapitalizedWord(_ word: String) -> Bool {
        !word.dropFirst().contains(where: \.isUppercase)
    }

    /// "I" and its contractions ("I'm", "I’ll").
    private static func isPronounI(_ word: String) -> Bool {
        guard word.first == "I" else { return false }
        let rest = word.dropFirst()
        return rest.isEmpty || rest.first == "'" || rest.first == "’"
    }

    private static func isVocabularyTerm(_ word: String, in vocabulary: [String]) -> Bool {
        vocabulary.contains { term in
            guard let first = term.split(whereSeparator: { !isWordPart($0) }).first else { return false }
            return first.caseInsensitiveCompare(word) == .orderedSame
        }
    }

    private static func replacing(letterAt index: String.Index, in text: String, with replacement: String) -> String {
        text.replacingCharacters(in: index...index, with: replacement)
    }

    // MARK: Trailing period

    /// Drops the final period of the text when the text after the cursor starts with punctuation that would repeat it.
    /// An ellipsis ("...") is not a period.
    private static func dropRepeatedPeriod(from text: String, after: String) -> String {
        guard let next = after.first, ".,;:!?…".contains(next), text.last == "." else { return text }
        let withoutLast = text.dropLast()
        guard withoutLast.last != "." else { return text }
        return String(withoutLast)
    }
}

extension String {
    fileprivate func trimmingTrailing(_ characters: String) -> Substring {
        var end = endIndex
        while end > startIndex, characters.contains(self[index(before: end)]) { end = index(before: end) }
        return self[startIndex..<end]
    }
}
