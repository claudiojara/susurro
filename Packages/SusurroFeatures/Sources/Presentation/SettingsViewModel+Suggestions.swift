import Domain
import Pipeline
import SusurroUI

extension SettingsViewModel {
    // MARK: Suggested terms

    /// The suggestions and the dismissed terms, which live in the settings store like everything else here.
    private var suggestionStore: SuggestionStore { SuggestionStore(settings: settings) }

    /// The suggested terms, most seen first, then the newest.
    var suggestionRows: [SuggestionRowState] {
        suggestionStore.suggestions()
            .sorted { ($0.count, $0.firstSeen) > ($1.count, $1.firstSeen) }
            .map { SuggestionRowState(term: $0.term, heard: $0.heard, count: $0.count) }
    }

    /// Adds the suggested term to the dictionary, where the recognizer and the cleaner get it, and drops the suggestion.
    /// A term the dictionary has already is only dropped.
    public func acceptSuggestion(_ id: String) {
        guard let suggestion = suggestionStore.suggestions().first(where: { $0.id == id }) else { return }
        try? dependencies.dictionary.add(suggestion.term)
        suggestionStore.remove(suggestion.term)
        changed()
    }

    public func dismissSuggestion(_ id: String) {
        guard let suggestion = suggestionStore.suggestions().first(where: { $0.id == id }) else { return }
        suggestionStore.dismiss(suggestion.term)
        changed()
    }

    public func setLearnFromCorrections(_ isOn: Bool) {
        settings.set(isOn, for: DictionarySettings.learnFromCorrections)
        changed()
    }
}
