/// Finds the proper nouns (names, organizations, places) in a text, on this Mac. The platform package implements it
/// with `NLTagger`.
public protocol EntityTagger: Sendable {
    func properNouns(in text: String) -> [String]
}

/// The user's own list of terms: names and words the recognizer and the cleaner should get right. Terms come in the
/// order the user keeps them.
public protocol UserDictionary: Sendable {
    func terms() -> [String]
    /// What the recognizer boosts and the cleaner is told to spell as given: the terms, then the written forms of the
    /// replacement rules that have a letter in them. The terms alone unless an implementation adds more.
    func vocabularyTerms() -> [String]
}

extension UserDictionary {
    public func vocabularyTerms() -> [String] { terms() }
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

/// The window a dictation goes to, as far as it is known: the app and, when the title is known, the window of that app. A
/// reading of the screen is kept only while the frontmost target is still this one.
public struct ScreenTarget: Sendable, Equatable {
    public let app: AppIdentity
    public let windowTitle: String?

    public init(app: AppIdentity, windowTitle: String? = nil) {
        self.app = app
        self.windowTitle = windowTitle
    }
}

/// Reads the text of a window on screen, on this Mac. Its output goes to the entity tagger and the vocabulary builder
/// and nowhere else.
public protocol ScreenTextRecognizer: Sendable {
    /// The lines of text found in the frontmost window of the target's app.
    func recognize(windowOf target: ScreenTarget) async throws -> [String]
}
