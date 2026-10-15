import DesignSystem
import SwiftUI

/// The terms suggested from the user's corrections, above the user's own words: each can be added to the dictionary or
/// dismissed for good. The switch turns the watching of corrections on and off. Nothing is ever added without a click.
struct SuggestedTermsCard: View {
    @Environment(\.theme) private var theme
    private let state: DictionarySettingsState
    private let actions: DictionaryActions
    private let query: String

    init(_ state: DictionarySettingsState, actions: DictionaryActions, query: String = "") {
        self.state = state
        self.actions = actions
        self.query = query
    }

    var body: some View {
        SettingsCard(Copy.title, footer: Copy.footer) {
            SettingsToggle(
                Copy.toggle, detail: Copy.detail, isOn: state.learnsFromCorrections,
                onChange: actions.learnFromCorrections)
            if state.suggestions.isEmpty {
                TextLabel(Copy.empty, tint: .neutral)
            } else if suggestions.isEmpty {
                TextLabel(DictionarySearch.noMatches, tint: .neutral)
            }
            ForEach(suggestions) { suggestion in
                HStack(spacing: theme.spacing(.sm)) {
                    VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                        TextLabel(suggestion.term, style: .bodyEmphasized)
                        TextLabel(Copy.heard(suggestion), style: .caption, tint: .neutral)
                    }
                    Spacer(minLength: theme.spacing(.sm))
                    ActionButton(Copy.add, kind: .primary) { actions.acceptSuggestion(suggestion.id) }
                    ActionButton(Copy.dismiss) { actions.dismissSuggestion(suggestion.id) }
                }
            }
        }
    }

    private var suggestions: [SuggestionRowState] {
        state.suggestions.filter { DictionarySearch.matches(query, $0.term, $0.heard) }
    }

    private enum Copy {
        static var title: String { L10n.string("suggested.title", "Suggested") }
        static var toggle: String { L10n.string("suggested.toggle", "Learn from my corrections") }
        static var detail: String {
            L10n.string(
                "suggested.detail",
                "After a dictation, Susurro looks once more at the field and notices names you fix by hand. It needs app context, and skips password fields and terminals."
            )
        }
        static var footer: String {
            L10n.string(
                "suggested.footer",
                "Only the corrected word and what was dictated are kept. The text of the field stays on this Mac and is never saved."
            )
        }
        static var empty: String { L10n.string("suggested.empty", "No suggestions yet.") }
        static var add: String { L10n.string("suggested.add", "Add") }
        static var dismiss: String { L10n.string("suggested.dismiss", "Dismiss") }

        static func heard(_ suggestion: SuggestionRowState) -> String {
            suggestion.count > 1
                ? L10n.string("suggested.heardRepeated", "Dictated as “\(suggestion.heard)”, \(suggestion.count) times")
                : L10n.string("suggested.heard", "Dictated as “\(suggestion.heard)”")
        }
    }
}

#Preview("SuggestedTermsCard") { PreviewMatrix { SuggestedTermsCard.Gallery() } }
