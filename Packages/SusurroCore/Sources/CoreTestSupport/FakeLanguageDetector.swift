import Domain

/// A language detector with scripted answers: the guesses for a text, found by the text itself, or by a part of it. A
/// text it knows nothing about has no guesses.
public struct FakeLanguageDetector: LanguageDetecting {
    private let answers: [String: [LanguageGuess]]

    public init(_ answers: [String: [LanguageGuess]] = [:]) {
        self.answers = answers
    }

    public func hypotheses(for text: String, maximum: Int) -> [LanguageGuess] {
        let guesses = answers[text] ?? answers.first { text.contains($0.key) }?.value ?? []
        return Array(guesses.prefix(maximum))
    }
}
