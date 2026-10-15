import Foundation

/// An override of the style for one app or site, as the settings list it.
public struct StyleOverrideEntry: Sendable, Equatable, Identifiable {
    public let target: StyleTarget
    public let override: StyleOverride

    public var id: StyleTarget { target }

    public init(target: StyleTarget, override: StyleOverride) {
        self.target = target
        self.override = override
    }
}

/// The style choices the user made: the tone of each category and the overrides for apps and sites. Reading never
/// fails; a value nobody set is the one the app ships with.
public protocol StylePreferencesStore: Sendable {
    /// The tone of a category: the user's, or the default of the table.
    func tone(for category: AppCategory) -> Tone
    /// Whether the user changed the tone of the category from the default.
    func isEdited(_ category: AppCategory) -> Bool
    /// Sets the tone of a category. Setting the default tone is the same as never having changed it.
    func setTone(_ tone: Tone, for category: AppCategory)
    /// The overrides, in the order they were added.
    func overrideEntries() -> [StyleOverrideEntry]
    /// Adds an override, or replaces the one for the same app or site. An override that sets neither a category nor a
    /// tone removes the existing one, since it would change nothing.
    func setOverride(_ override: StyleOverride, for target: StyleTarget)
    func removeOverride(for target: StyleTarget)
}

/// The user's own words, which the recognizer and the cleanup are asked to spell as given.
public protocol DictionaryTermStore: Sendable {
    /// The terms, in the order they were added.
    func terms() -> [String]
    /// Throws `DictionaryError` when the term is empty, too long, or repeats another one.
    func add(_ term: String) throws
    /// Replaces `old` with `new`. The new term follows the same rules as an added one. A missing `old` changes nothing.
    func edit(_ old: String, to new: String) throws
    func remove(_ term: String)

    /// The replacement rules, in the order they were added.
    func replacements() -> [ReplacementRule]
    /// Throws `DictionaryError` when a form is empty or too long, or another rule has the same spoken form (case and
    /// accents ignored).
    func addReplacement(_ rule: ReplacementRule) throws
    /// Replaces the rule for `spoken` with `rule`, in the same place. A missing rule changes nothing.
    func editReplacement(_ spoken: String, to rule: ReplacementRule) throws
    func removeReplacement(_ spoken: String)

    /// The voice snippets, in the order they were added.
    func snippets() -> [VoiceSnippet]
    /// Throws `DictionaryError` when the trigger or the text is empty or too long, or another snippet has the same
    /// trigger (case and accents ignored).
    func addSnippet(_ snippet: VoiceSnippet) throws
    /// Replaces the snippet of `trigger` with `snippet`, in the same place. A missing snippet changes nothing.
    func editSnippet(_ trigger: String, to snippet: VoiceSnippet) throws
    func removeSnippet(_ trigger: String)
}

/// Why a dictionary edit was refused.
public enum DictionaryError: Error, Sendable, Equatable {
    case empty
    /// Another term is the same when case is ignored.
    case duplicate
    /// The term is longer than `VocabularyLimits.maxTermLength`.
    case tooLong
    case notFound
}

/// How the app is drawn: the system's light or dark, or always one of them.
public enum AppearanceMode: String, Sendable, Equatable, CaseIterable {
    case system, light, dark
}

/// The settings of the Appearance tab.
public enum AppearanceSettings {
    /// The id of the theme in use: `default`, or the name of a theme file in the themes folder.
    public static let theme = SettingKey<String>(area: "appearance", name: "theme", default: "default")
    public static let mode = SettingKey<AppearanceMode>(area: "appearance", name: "mode", default: .system)

    public static var all: [any AnySettingKey] { [theme, mode] }
}
