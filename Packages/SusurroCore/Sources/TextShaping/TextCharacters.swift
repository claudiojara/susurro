import Foundation

/// The character classes the guard and the insertion shaper agree on, so a "sentence end" or a "word character" means
/// one thing in both.
enum TextCharacters {
    /// Ends a sentence. `¿` and `¡` open one, so they are not here.
    static func isSentenceTerminator(_ character: Character) -> Bool {
        ".!?…。".contains(character)
    }

    /// Punctuation that closes a phrase or separates it from the word before it, and so is written with no space before.
    /// An opening mark (`¿`, `¡`, `(`, an opening quote) is not in it, and neither is a straight quote, which can open
    /// or close.
    static func isClosingPunctuation(_ character: Character) -> Bool {
        ".,;:!?…)]}»”’%。、，！？".contains(character)
    }

    /// A character of a word: a letter, a digit, or an underscore.
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// The text as the guard compares it: lowercase, without accents, with one kind of apostrophe.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacing("’", with: "'")
            .replacing("‘", with: "'")
    }
}
