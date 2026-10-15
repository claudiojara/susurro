import Domain
import Foundation
import SusurroUI

extension SettingsViewModel {
    // MARK: Dictionary tab

    /// The suggested terms, the terms, the replacement rules, the snippets, and the filler switch, with the reason the last change of each
    /// list was refused.
    var dictionaryState: DictionarySettingsState {
        let dictionary = dependencies.dictionary
        return DictionarySettingsState(
            terms: dictionary.terms(), error: dictionaryError,
            replacements: dictionary.replacements().map { ReplacementRowState(spoken: $0.spoken, written: $0.written) },
            replacementError: replacementError,
            snippets: dictionary.snippets().map { SnippetRowState(trigger: $0.trigger, text: $0.text) },
            snippetError: snippetError,
            removesFillers: settings.value(for: TextRuleSettings.removeFillers),
            suggestions: suggestionRows,
            learnsFromCorrections: settings.value(for: DictionarySettings.learnFromCorrections))
    }

    // MARK: Replacements

    public func addReplacement(spoken: String, written: String) {
        replacementError = refusal(TextRulesCopy.replacementRefusal) {
            try dependencies.dictionary.addReplacement(ReplacementRule(spoken: spoken, written: written))
        }
        changed()
    }

    public func editReplacement(_ old: String, spoken: String, written: String) {
        replacementError = refusal(TextRulesCopy.replacementRefusal) {
            try dependencies.dictionary.editReplacement(old, to: ReplacementRule(spoken: spoken, written: written))
        }
        changed()
    }

    public func removeReplacement(_ spoken: String) {
        dependencies.dictionary.removeReplacement(spoken)
        replacementError = nil
        changed()
    }

    // MARK: Snippets

    public func addSnippet(trigger: String, text: String) {
        snippetError = refusal(TextRulesCopy.snippetRefusal) {
            try dependencies.dictionary.addSnippet(VoiceSnippet(trigger: trigger, text: text))
        }
        changed()
    }

    public func editSnippet(_ old: String, trigger: String, text: String) {
        snippetError = refusal(TextRulesCopy.snippetRefusal) {
            try dependencies.dictionary.editSnippet(old, to: VoiceSnippet(trigger: trigger, text: text))
        }
        changed()
    }

    public func removeSnippet(_ trigger: String) {
        dependencies.dictionary.removeSnippet(trigger)
        snippetError = nil
        changed()
    }

    // MARK: Fillers

    public func setRemoveFillers(_ isOn: Bool) {
        settings.set(isOn, for: TextRuleSettings.removeFillers)
        changed()
    }

    /// Runs the change and gives the reason it was refused, or nil when it was made.
    private func refusal(_ reason: (DictionaryError) -> String?, _ change: () throws -> Void) -> String? {
        do {
            try change()
            return nil
        } catch let error as DictionaryError {
            return reason(error)
        } catch {
            return reason(.empty)
        }
    }
}
