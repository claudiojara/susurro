import Foundation

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
    func overrides() -> [StyleOverride]
    /// Adds an override, or replaces the one for the same app or site. An override with neither a category nor a tone
    /// removes the existing one, since it would change nothing.
    func setOverride(_ override: StyleOverride)
    func removeOverride(for target: StyleTarget)
}

/// The user's own words, which the recognizer and the cleanup are asked to spell as given.
public protocol DictionaryTermStore: Sendable {
    /// The terms, in the order they were added.
    func terms() -> [String]
    func add(_ term: String) throws
    /// Replaces `old` with `new`. The new term follows the same rules as an added one.
    func edit(_ old: String, to new: String) throws
    func remove(_ term: String)
}

/// Why a dictionary term was refused.
public enum DictionaryTermError: Error, Sendable, Equatable {
    case empty
    /// Another term is the same when case is ignored.
    case duplicate
    /// The term is longer than the dictionary keeps.
    case tooLong(limit: Int)
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
