import Domain
import Foundation

/// What the vocabulary is built from, for one dictation. Field text, selection, and screen text are in memory only for
/// the dictation: the builder keeps none of them, and only the proper nouns found in them leave it.
public struct VocabularySources: Sendable, Equatable {
    /// The user's dictionary, in the order they keep it.
    public let dictionary: [String]
    public let beforeCursor: String
    public let afterCursor: String
    public let selection: String
    /// Lines of text read from the screen with OCR, when the user turned it on.
    public let screenText: [String]
    /// Whether the focused field is a secure one. Nothing is extracted from a secure field.
    public let isSecureField: Bool

    public init(
        dictionary: [String] = [], beforeCursor: String = "", afterCursor: String = "", selection: String = "",
        screenText: [String] = [], isSecureField: Bool = false
    ) {
        self.dictionary = dictionary
        self.beforeCursor = beforeCursor
        self.afterCursor = afterCursor
        self.selection = selection
        self.screenText = screenText
        self.isSecureField = isSecureField
    }
}

/// Merges the user's dictionary with the proper nouns found around the cursor and on screen into one bounded list of
/// terms for the recognizer and the cleaner.
///
/// The priority is the dictionary first, then the nouns of the field and the selection, then the nouns of the screen.
/// The list is deduplicated without regard to case, so the spelling of the higher priority wins, and it is bounded
/// (50 terms of at most 40 characters by default). The dictionary comes first, so context terms never push it out.
public struct VocabularyBuilder: Sendable {
    public static let defaultMaxTerms = VocabularyLimits.maxTerms
    public static let defaultMaxTermLength = VocabularyLimits.maxTermLength

    private let tagger: any EntityTagger
    private let maxTerms: Int
    private let maxTermLength: Int

    public init(
        tagger: any EntityTagger, maxTerms: Int = defaultMaxTerms, maxTermLength: Int = defaultMaxTermLength
    ) {
        self.tagger = tagger
        self.maxTerms = maxTerms
        self.maxTermLength = maxTermLength
    }

    public func build(_ sources: VocabularySources) -> [String] {
        var terms: [String] = []
        var seen: Set<String> = []

        func add(_ candidates: [String]) {
            for candidate in candidates where terms.count < maxTerms {
                let term = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty, term.count <= maxTermLength, seen.insert(term.lowercased()).inserted else {
                    continue
                }
                terms.append(term)
            }
        }

        add(sources.dictionary)
        guard !sources.isSecureField else { return terms }
        for text in [sources.beforeCursor, sources.afterCursor, sources.selection] { add(nouns(in: text)) }
        for line in sources.screenText { add(nouns(in: line)) }
        return terms
    }

    private func nouns(in text: String) -> [String] {
        guard !text.allSatisfy(\.isWhitespace) else { return [] }
        return tagger.properNouns(in: text)
    }
}
