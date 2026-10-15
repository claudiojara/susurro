/// A rule of the user's dictionary that writes a spoken form another way: "jira" as "Jira", "punto com" as ".com". It
/// matches whole words, ignoring case and accents.
public struct ReplacementRule: Sendable, Equatable, Hashable, Codable {
    public let spoken: String
    public let written: String

    public init(spoken: String, written: String) {
        self.spoken = spoken
        self.written = written
    }
}

/// A text the user keeps under a phrase: saying the phrase inserts the text, which can span several lines.
public struct VoiceSnippet: Sendable, Equatable, Hashable, Codable {
    public let trigger: String
    public let text: String

    public init(trigger: String, text: String) {
        self.trigger = trigger
        self.text = text
    }
}

/// The bounds of the replacement rules and the snippets the user can keep.
public enum TextRuleLimits {
    /// The most characters in a spoken form, a written form, or a trigger.
    public static let maxPhraseLength = 80
    /// The most characters in the text of a snippet.
    public static let maxSnippetLength = 2_000
}

/// The settings of the deterministic text passes that run on every dictation, with or without a cleaner.
public enum TextRuleSettings {
    /// The replacement rules, in the order the user keeps them.
    public static let replacements = SettingKey<[ReplacementRule]>.json(
        area: "dictionary", name: "replacements", default: [])
    /// The voice snippets, in the order the user keeps them.
    public static let snippets = SettingKey<[VoiceSnippet]>.json(area: "snippets", name: "items", default: [])
    /// Whether hesitations ("eh", "erm") and simple self-corrections ("a las 2, no, a las 3") are removed. On by default.
    public static let removeFillers = SettingKey<Bool>(area: "cleanup", name: "removeFillers", default: true)

    public static var all: [any AnySettingKey] { [replacements, snippets, removeFillers, DictionarySettings.terms] }
}
