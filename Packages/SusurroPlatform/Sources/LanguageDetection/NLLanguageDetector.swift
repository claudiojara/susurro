import Domain
import NaturalLanguage

/// Tells the language of a text with the system's language recognizer. It runs on this Mac and sends nothing anywhere.
public struct NLLanguageDetector: LanguageDetecting {
    public init() {}

    public func hypotheses(for text: String, maximum: Int) -> [LanguageGuess] {
        guard !text.allSatisfy(\.isWhitespace), maximum > 0 else { return [] }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: maximum)
            .sorted { $0.value > $1.value }
            .map { LanguageGuess(code: $0.key.rawValue, confidence: $0.value) }
    }
}
