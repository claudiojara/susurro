import Domain

/// Writes the spoken forms of the user's replacement rules as the rules say ("jira" as "Jira"). A rule matches whole
/// words, ignoring case and accents (ñ is a letter of its own); where two rules could match at one place the one with more
/// words wins; and a text a rule wrote is not matched again. It is deterministic and runs in one pass over the text.
public struct ReplacementApplier: Sendable {
    private struct Rule: Sendable {
        let phrase: Phrase
        let written: String
    }

    /// The rules that can start at a word, by the key of that word, longest first.
    private let rules: [String: [Rule]]

    public init(rules: [ReplacementRule]) {
        var byKey: [String: [Rule]] = [:]
        for rule in rules {
            let phrase = Phrase(rule.spoken)
            guard !phrase.isEmpty else { continue }
            byKey[phrase.firstKey, default: []].append(Rule(phrase: phrase, written: rule.written))
        }
        self.rules = byKey.mapValues { $0.sorted { $0.phrase.pieces.count > $1.phrase.pieces.count } }
    }

    public var isEmpty: Bool { rules.isEmpty }

    public func apply(_ text: String) -> String {
        guard !rules.isEmpty else { return text }
        let pieces = WordLexer.pieces(of: text)
        var output = ""
        var changed = false
        var index = 0
        while index < pieces.count {
            let piece = pieces[index]
            if piece.isWord, let candidates = rules[piece.key], index == 0 || !pieces[index - 1].isWord,
                let (rule, length) = firstMatch(of: candidates, in: pieces, at: index)
            {
                output += rule.written
                index += length
                changed = true
                continue
            }
            output += piece.text
            index += 1
        }
        return changed ? output : text
    }

    private func firstMatch(of candidates: [Rule], in pieces: [TextPiece], at index: Int) -> (Rule, Int)? {
        for rule in candidates {
            guard let length = rule.phrase.matchLength(in: pieces, at: index) else { continue }
            if Self.continuesWord(pieces, after: index + length) { continue }
            return (rule, length)
        }
        return nil
    }

    /// Whether the text goes on with a part of the same word after a match: an apostrophe and a letter ("jira's").
    static func continuesWord(_ pieces: [TextPiece], after end: Int) -> Bool {
        guard end + 1 < pieces.count, pieces[end].isPunctuation, pieces[end + 1].isWord else { return false }
        return pieces[end].text == "'" || pieces[end].text == "’"
    }
}
