/// How likely a text is in a language, by the language's code ("es", "en").
public struct LanguageGuess: Sendable, Equatable {
    public let code: String
    /// From 0 to 1.
    public let confidence: Double

    public init(code: String, confidence: Double) {
        self.code = code
        self.confidence = confidence
    }
}

/// Tells what language a text is in. The pipeline uses it to notice a transcript that came back in the wrong language.
public protocol LanguageDetecting: Sendable {
    /// The most likely languages of `text`, the likeliest first, at most `maximum`. Empty when the text is too short or
    /// too odd to tell.
    func hypotheses(for text: String, maximum: Int) -> [LanguageGuess]
}
