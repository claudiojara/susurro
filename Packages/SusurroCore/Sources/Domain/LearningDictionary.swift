import Foundation

/// A term the app noticed the user correcting after a dictation, offered for the dictionary. It is never added on its
/// own: the user accepts or dismisses it in the settings.
///
/// It keeps only the corrected word and what the dictation had written in its place, which is a fragment of the app's
/// own output (already in the history). Nothing of the field around it is kept.
public struct DictionarySuggestion: Sendable, Equatable, Codable, Identifiable {
    /// The spelling the user typed.
    public let term: String
    /// What the dictation wrote instead.
    public let heard: String
    /// How many times the same correction was seen.
    public var count: Int
    public let firstSeen: Date

    /// Two suggestions that differ only in case are one.
    public var id: String { term.lowercased() }

    public init(term: String, heard: String, count: Int = 1, firstSeen: Date) {
        self.term = term
        self.heard = heard
        self.count = count
        self.firstSeen = firstSeen
    }
}

/// Keeps the suggested terms and the ones the user dismissed. The suggestions are bounded, and a dismissed term is never
/// suggested again.
public protocol DictionarySuggestionStore: Sendable {
    /// The suggestions, oldest first.
    func suggestions() -> [DictionarySuggestion]
    /// The terms the user dismissed, as they were spelled.
    func dismissed() -> [String]
    /// Adds a suggestion, or counts it again when it is there already (case ignored). The oldest is dropped when the
    /// list is full.
    func record(term: String, heard: String, at date: Date)
    /// Drops the suggestion, as when it was accepted. A term that is not there is ignored.
    func remove(_ term: String)
    /// Drops the suggestion and keeps the term out of later suggestions.
    func dismiss(_ term: String)
}

extension DictionarySettings {
    /// Whether the app watches for corrections after a dictation and suggests the corrected words. On by default; it
    /// also needs "use app context", and never looks at a secure field or a terminal.
    public static let learnFromCorrections = SettingKey<Bool>(
        area: "dictionary", name: "learnFromCorrections", default: true)
    /// The suggested terms, at most `DictionarySuggestionLimits.maxSuggestions`.
    public static let suggestions = SettingKey<[DictionarySuggestion]>.json(
        area: "dictionary", name: "suggestions", default: [])
    /// The terms the user dismissed.
    public static let dismissed = SettingKey<[String]>.json(area: "dictionary", name: "dismissed", default: [])

    /// The keys of the dictionary, for the check that no two share a name.
    public static let all: [any AnySettingKey] = [terms, learnFromCorrections, suggestions, dismissed]
}

/// The bounds of the suggestion lists.
public enum DictionarySuggestionLimits {
    /// The most suggestions kept; the oldest goes first.
    public static let maxSuggestions = 20
    /// The most dismissed terms kept; the oldest goes first.
    public static let maxDismissed = 200
}

/// Why the watch of one dictation's corrections ended. The diagnostics line carries this and nothing of the text.
public enum CorrectionWatchEnd: String, Sendable, Equatable {
    /// At least one corrected word was suggested.
    case suggested
    /// The text was found and nothing in it was a correction worth a term.
    case noCorrection
    /// The text around the dictation was not there any more (a sent message, a cleared field) or the field was too big.
    case anchorLost
    /// Another app was in front.
    case appSwitched
    /// The field could not be read, or was a secure one.
    case unreadable
    /// A newer dictation was watched instead.
    case replaced
}
