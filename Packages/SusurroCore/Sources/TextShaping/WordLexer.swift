import Foundation

/// A piece of a text as the deterministic passes see it: a word, a run of white space, or a run of punctuation. Joining
/// the pieces of a text gives the text back exactly.
struct TextPiece: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case word, space, punctuation
    }

    let kind: Kind
    let text: String

    /// The word as rules compare it: lowercase and without accents, ñ kept apart from n. Empty for other pieces.
    let key: String

    init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
        key = kind == .word ? WordFolding.fold(text) : ""
    }

    var isWord: Bool { kind == .word }
    var isSpace: Bool { kind == .space }
    var isPunctuation: Bool { kind == .punctuation }
}

/// Splits a text into words, white space, and punctuation. A word is a run of letters, digits, and underscores, with an
/// apostrophe inside it ("don't", "Let's"); a hyphen splits words.
enum WordLexer {
    static func pieces(of text: String) -> [TextPiece] {
        let characters = Array(text)
        var pieces: [TextPiece] = []
        var index = 0
        while index < characters.count {
            let start = index
            let kind = kind(at: index, in: characters)
            index += 1
            while index < characters.count, self.kind(at: index, in: characters) == kind { index += 1 }
            pieces.append(TextPiece(kind, String(characters[start..<index])))
        }
        return pieces
    }

    private static func kind(at index: Int, in characters: [Character]) -> TextPiece.Kind {
        let character = characters[index]
        if TextCharacters.isWordCharacter(character) { return .word }
        if character.isWhitespace { return .space }
        if character == "'" || character == "’", index > 0, index + 1 < characters.count,
            TextCharacters.isWordCharacter(characters[index - 1]), TextCharacters.isWordCharacter(characters[index + 1])
        {
            return .word
        }
        return .punctuation
    }
}

/// How rules compare words: case and accents are ignored, but ñ stays a letter of its own, since "año" and "ano" are
/// different words.
enum WordFolding {
    static func fold(_ word: String) -> String {
        let lower = word.lowercased()
        guard !lower.allSatisfy(\.isASCII) else { return lower }
        return lower.split(separator: "ñ", omittingEmptySubsequences: false)
            .map { $0.folding(options: [.diacriticInsensitive], locale: nil) }
            .joined(separator: "ñ")
            .replacing("’", with: "'")
    }
}
