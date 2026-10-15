import Domain
import Foundation

/// Decides which of the user's corrections are worth a dictionary term: a name or a word the recognizer misheard, not a
/// rewording, a typo fix of a common word, or a word the dictionary has already.
///
/// A correction is suggested when the corrected side
/// - is 5 to 40 characters (shorter terms are not boosted by the recognizer, and longer ones cannot be kept),
/// - is made of words of letters, digits, hyphens, and apostrophes, and is not only digits,
/// - is not a stopword,
/// - is not in the dictionary or among the dismissed terms (case ignored),
/// - is close in spelling to what was heard (a normalized edit distance of at most 0.5, spaces and punctuation ignored),
/// - and looks like a name: it has a capital letter, or the entity tagger calls it a proper noun.
public struct SuggestionFilter: Sendable {
    public static let minimumLength = 5
    public static let maximumDistance = 0.5

    private let tagger: any EntityTagger

    public init(tagger: any EntityTagger) {
        self.tagger = tagger
    }

    /// The corrections worth suggesting, each term once, in order.
    ///
    /// - Parameters:
    ///   - text: The text the corrections were found in, which the tagger reads. It is used here and dropped.
    ///   - known: The terms of the dictionary and the dismissed ones.
    public func suggestions(from corrections: [WordCorrection], in text: String, known: [String]) -> [WordCorrection] {
        var seen = Set(known.map { $0.lowercased() })
        return corrections.filter { correction in
            accepts(correction, in: text, known: []) && seen.insert(correction.corrected.lowercased()).inserted
        }
    }

    /// Whether one correction is worth suggesting.
    public func accepts(_ correction: WordCorrection, in text: String, known: [String]) -> Bool {
        let term = correction.corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (Self.minimumLength...VocabularyLimits.maxTermLength).contains(term.count) else { return false }
        let words = term.split(separator: " ")
        guard words.allSatisfy(Self.isTermWord), !term.allSatisfy({ $0.isNumber || $0 == " " }) else { return false }
        guard !words.allSatisfy({ Stopwords.contains(TextCharacters.folded(String($0))) }) else { return false }
        let lowered = term.lowercased()
        guard !known.contains(where: { $0.lowercased() == lowered }) else { return false }
        guard Self.distance(correction.heard, term) <= Self.maximumDistance else { return false }
        return term.contains(where: \.isUppercase)
            || tagger.properNouns(in: text).contains { $0.lowercased() == lowered }
    }

    private static func isTermWord(_ word: Substring) -> Bool {
        word.allSatisfy { $0.isLetter || $0.isNumber || "-'’".contains($0) }
    }

    /// The edit distance of the two sides, folded and with only their letters and digits, over the longer one.
    static func distance(_ a: String, _ b: String) -> Double {
        let a = Array(TextCharacters.folded(a).filter { $0.isLetter || $0.isNumber })
        let b = Array(TextCharacters.folded(b).filter { $0.isLetter || $0.isNumber })
        let longest = max(a.count, b.count)
        guard !a.isEmpty, !b.isEmpty else { return longest > 0 ? 1 : 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        let edits = previous[b.count]
        return Double(edits) / Double(longest)
    }
}
