import Domain

/// The deterministic passes of a dictation, in the order they run: voice snippets on the raw transcript, then filler
/// removal, then the replacement rules. Spacing and capitalization for the field come after, in `InsertionShaper`. They
/// run whether or not a cleaner does, and add well under a millisecond to a dictation of ordinary length.
///
/// A snippet is matched two ways. A dictation that is only a trigger (ignoring case, accents and punctuation) becomes the
/// snippet. A trigger of two words or more said inside a dictation, as that exact phrase, is expanded where it was said;
/// a one-word trigger is not, since a single word is said for other reasons too. The text of a snippet is the user's own,
/// so no other pass touches it.
public struct TranscriptRules: Sendable {
    /// The text after the passes, and whether a snippet was expanded inside it.
    public struct Result: Sendable, Equatable {
        public let text: String
        public let expandedSnippet: Bool
    }

    private struct Snippet: Sendable {
        let phrase: Phrase
        let text: String
    }

    private let wholeSnippets: [[String]: String]
    private let inlineSnippets: [String: [Snippet]]
    private let replacements: ReplacementApplier
    public let removesFillers: Bool

    public static let none = TranscriptRules(snippets: [], replacements: [], removesFillers: false)

    public init(snippets: [VoiceSnippet], replacements: [ReplacementRule], removesFillers: Bool) {
        var whole: [[String]: String] = [:]
        var inline: [String: [Snippet]] = [:]
        for snippet in snippets {
            let phrase = Phrase(snippet.trigger)
            guard !phrase.isEmpty else { continue }
            if whole[phrase.keys] == nil { whole[phrase.keys] = snippet.text }
            if phrase.wordCount >= 2 {
                inline[phrase.firstKey, default: []].append(Snippet(phrase: phrase, text: snippet.text))
            }
        }
        wholeSnippets = whole
        inlineSnippets = inline.mapValues { $0.sorted { $0.phrase.pieces.count > $1.phrase.pieces.count } }
        self.replacements = ReplacementApplier(rules: replacements)
        self.removesFillers = removesFillers
    }

    /// A copy that removes fillers or not, the rest unchanged.
    public func removingFillers(_ isOn: Bool) -> TranscriptRules {
        TranscriptRules(self, removesFillers: isOn)
    }

    private init(_ other: TranscriptRules, removesFillers: Bool) {
        wholeSnippets = other.wholeSnippets
        inlineSnippets = other.inlineSnippets
        replacements = other.replacements
        self.removesFillers = removesFillers
    }

    /// The snippet whose trigger is the whole dictation, or nil.
    public func snippet(matching transcript: String) -> String? {
        guard !wholeSnippets.isEmpty else { return nil }
        let keys = WordLexer.pieces(of: transcript).filter(\.isWord).map(\.key)
        guard !keys.isEmpty else { return nil }
        return wholeSnippets[keys]
    }

    /// The transcript after inline snippets, filler removal, and replacements.
    public func apply(to transcript: String) -> Result {
        var output = ""
        var expanded = false
        for segment in segments(of: transcript) {
            switch segment {
            case .snippet(let text):
                output += text
                expanded = true
            case .dictated(let text):
                output += shaped(text)
            }
        }
        return Result(text: output, expandedSnippet: expanded)
    }

    private func shaped(_ text: String) -> String {
        let cleaned = removesFillers ? FillerRemover.clean(text) : text
        return replacements.apply(cleaned)
    }

    // MARK: Inline snippets

    private enum Segment {
        case dictated(String)
        case snippet(String)
    }

    /// The transcript cut where inline triggers were said, each trigger replaced by its snippet.
    private func segments(of transcript: String) -> [Segment] {
        guard !inlineSnippets.isEmpty else { return [.dictated(transcript)] }
        let pieces = WordLexer.pieces(of: transcript)
        var segments: [Segment] = []
        var dictated = ""
        var index = 0
        while index < pieces.count {
            let piece = pieces[index]
            if piece.isWord, index == 0 || !pieces[index - 1].isWord, let candidates = inlineSnippets[piece.key],
                let (snippet, length) = firstMatch(of: candidates, in: pieces, at: index)
            {
                if !dictated.isEmpty { segments.append(.dictated(dictated)) }
                dictated = ""
                segments.append(.snippet(snippet.text))
                index += length
                continue
            }
            dictated += piece.text
            index += 1
        }
        if !dictated.isEmpty { segments.append(.dictated(dictated)) }
        return segments
    }

    private func firstMatch(of candidates: [Snippet], in pieces: [TextPiece], at index: Int) -> (Snippet, Int)? {
        for snippet in candidates {
            guard let length = snippet.phrase.matchLength(in: pieces, at: index),
                !ReplacementApplier.continuesWord(pieces, after: index + length)
            else { continue }
            return (snippet, length)
        }
        return nil
    }
}
