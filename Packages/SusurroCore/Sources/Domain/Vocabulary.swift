/// Finds the proper nouns (names, organizations, places) in a text, on this Mac. The platform package implements it
/// with `NLTagger`.
public protocol EntityTagger: Sendable {
    func properNouns(in text: String) -> [String]
}

/// The user's own list of terms: names and words the recognizer and the cleaner should get right. Terms come in the
/// order the user keeps them.
public protocol UserDictionary: Sendable {
    func terms() -> [String]
}

/// The bounds of the vocabulary that the recognizer and the cleaner receive, and of the terms the user can keep.
public enum VocabularyLimits {
    /// The most terms in one dictation's vocabulary.
    public static let maxTerms = 50
    /// The most characters in one term.
    public static let maxTermLength = 40
}

public enum DictionarySettings {
    /// The user's dictionary: one list under one key, in the order the user keeps it.
    public static let terms = SettingKey<[String]>.json(area: "dictionary", name: "terms", default: [])
}

/// Reads the text of a window on screen, on this Mac. Its output goes to the entity tagger and the vocabulary builder
/// and nowhere else.
public protocol ScreenTextRecognizer: Sendable {
    /// The lines of text found in the frontmost window of `app`.
    func recognize(windowOf app: AppIdentity) async throws -> [String]
}
