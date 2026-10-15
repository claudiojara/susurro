/// Removes hesitations and simple self-corrections from a transcript, by rule and without a model. The rules are
/// conservative: a word that can be a real word ("um" is Portuguese, "like" and "o sea" carry meaning, "este" is a
/// demonstrative) is left, and a text where nothing matched comes back exactly as it was.
///
/// - Hesitations: "eh", "em", "mmm", "hmm", "erm", "umm", "uhh", "uhm" and their stretched spellings, and "este" right
///   before an ellipsis with more words after it. A tag question ("¿eh?") and a word glued to an apostrophe or a hyphen
///   ("'em", "ehm-test") stay, and so does an acronym written in capitals ("ERM", "HM Treasury"). The commas the
///   hesitation brought go with it, and a sentence it began starts with a capital.
/// - Self-corrections: "X, no, Y" (also "digo", "mejor dicho") where Y starts with the same word as X, X is two to six
///   words of the same clause, and Y starts with neither a "no" or a "yes" nor a personal pronoun. X and the marker go;
///   Y stays.
public enum FillerRemover {
    public static func clean(_ text: String) -> String {
        var pieces = WordLexer.pieces(of: text)
        var changed = removeHesitations(&pieces)
        changed = SelfCorrection.apply(&pieces) || changed
        guard changed, pieces.contains(where: \.isWord) else { return text }
        return pieces.map(\.text).joined()
    }

    // MARK: Hesitations

    private static func removeHesitations(_ pieces: inout [TextPiece]) -> Bool {
        var changed = false
        var index = 0
        while index < pieces.count {
            if pieces[index].isWord, isHesitation(at: index, in: pieces),
                pieces.indices.contains(where: { $0 != index && pieces[$0].isWord })
            {
                remove(at: index, from: &pieces)
                changed = true
            } else {
                index += 1
            }
        }
        return changed
    }

    /// Spellings of a hesitation, as folded keys. "um" and "uh" are not here: they are words in other languages, and the
    /// recognizer writes them for real speech too.
    ///
    /// A spelling is read as its runs of one letter: "ehhh" is `e` then `h`. The shapes are e+h+, e+m+, e+h+m+, m{2,},
    /// h+m+, e+r+m+, u+m{2,}, u+h{2,} and u+h+m+. It is written out rather than as a regular expression, which costs
    /// about a hundred times more for each word.
    private static func isHesitationWord(_ key: String) -> Bool {
        guard key.utf8.count <= 12, key.allSatisfy(\.isASCII) else { return false }
        var letters = ""
        var counts: [Int] = []
        for character in key {
            if letters.last == character {
                counts[counts.count - 1] += 1
            } else {
                letters.append(character)
                counts.append(1)
            }
        }
        switch letters {
        case "eh", "em", "ehm", "hm", "erm", "uhm": return true
        case "m": return counts[0] >= 2
        case "um", "uh": return counts[1] >= 2
        default: return false
        }
    }

    private static func isHesitation(at index: Int, in pieces: [TextPiece]) -> Bool {
        let key = pieces[index].key
        let previous = index > 0 ? pieces[index - 1] : nil
        let next = index + 1 < pieces.count ? pieces[index + 1] : nil
        // Glued to an apostrophe or a hyphen: part of something else ("'em", "ehm-test").
        if let previous, previous.isPunctuation, previous.text.last.map({ "'’-".contains($0) }) == true { return false }
        if let next, next.isPunctuation, next.text.first.map({ "'’-".contains($0) }) == true { return false }
        // A tag question, "¿eh?".
        if let after = neighbor(of: index, in: pieces, step: 1), after.isPunctuation, after.text.hasPrefix("?") {
            return false
        }
        if let before = neighbor(of: index, in: pieces, step: -1), before.isPunctuation, before.text.contains("¿") {
            return false
        }
        if key == "este" {
            guard let next, next.isPunctuation, isEllipsis(next.text) else { return false }
            return pieces[(index + 2)...].contains(where: \.isWord)
        }
        return !isAcronym(pieces[index].text) && isHesitationWord(key)
    }

    /// A word with a capital after its first letter, as an acronym is written ("ERM", "HM"): never a hesitation.
    private static func isAcronym(_ word: String) -> Bool {
        word.dropFirst().contains(where: \.isUppercase)
    }

    /// Removes the hesitation at `index`, the comma or ellipsis after it, and the space after that. At the start of a
    /// sentence any pause mark after it goes too, and the next word takes the capital. A comma before it that would now
    /// stand before a period, or at the end, goes as well.
    private static func remove(at index: Int, from pieces: inout [TextPiece]) {
        let startsSentence = isSentenceStart(before: index, in: pieces)
        let wasCapitalized = pieces[index].text.first?.isUppercase == true
        var end = index + 1
        if end < pieces.count, pieces[end].isPunctuation,
            isPause(pieces[end].text) || (startsSentence && pieces[end].text.allSatisfy { ".,;:…".contains($0) })
        {
            end += 1
        }
        if end < pieces.count, pieces[end].isSpace, !pieces[end].text.contains(where: \.isNewline) { end += 1 }
        pieces.removeSubrange(index..<end)

        let closesHere = index == pieces.count || (pieces[index].isPunctuation && isClosing(pieces[index].text))
        if closesHere {
            var start = index
            if start > 0, pieces[start - 1].isSpace, !pieces[start - 1].text.contains(where: \.isNewline) { start -= 1 }
            if start > 0, pieces[start - 1].isPunctuation, pieces[start - 1].text == "," { start -= 1 }
            pieces.removeSubrange(start..<index)
        }
        if startsSentence && wasCapitalized { capitalizeWord(from: index, in: &pieces) }
    }

    private static func neighbor(of index: Int, in pieces: [TextPiece], step: Int) -> TextPiece? {
        var position = index + step
        while pieces.indices.contains(position) {
            if !pieces[position].isSpace { return pieces[position] }
            position += step
        }
        return nil
    }

    /// Whether a sentence starts at `index`: nothing but space before it, or a sentence end.
    static func isSentenceStart(before index: Int, in pieces: [TextPiece]) -> Bool {
        guard let previous = neighbor(of: index, in: pieces, step: -1) else { return true }
        return previous.isPunctuation && previous.text.last.map(TextCharacters.isSentenceTerminator) == true
    }

    private static func isEllipsis(_ text: String) -> Bool {
        text.hasPrefix("...") || text.hasPrefix("…")
    }

    /// A comma or an ellipsis: the marks a hesitation brings.
    private static func isPause(_ text: String) -> Bool {
        text == "," || text == "..." || text == "…" || text == ",..."
    }

    /// Punctuation that ends a phrase, so a comma before it has nothing to separate.
    private static func isClosing(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return TextCharacters.isClosingPunctuation(first)
    }

    /// Gives the first letter at or after `index` a capital, if it is a word's.
    static func capitalizeWord(from index: Int, in pieces: inout [TextPiece]) {
        guard let position = pieces[index...].firstIndex(where: \.isWord) else { return }
        let word = pieces[position].text
        guard let first = word.first, first.isLowercase else { return }
        pieces[position] = TextPiece(.word, first.uppercased() + word.dropFirst())
    }
}
