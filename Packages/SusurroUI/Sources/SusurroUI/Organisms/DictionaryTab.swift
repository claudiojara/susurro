import DesignSystem
import Foundation
import SwiftUI

/// The Dictionary tab: a search over everything in it, then the suggested terms, the user's terms, the replacement rules, the voice snippets,
/// and the switch that removes filler words. The search lives here and narrows every list at once.
struct DictionaryTab: View {
    @Environment(\.theme) private var theme
    private let state: DictionarySettingsState
    private let actions: DictionaryActions
    @State private var query = ""

    init(_ state: DictionarySettingsState, actions: DictionaryActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
            HStack(spacing: theme.spacing(.sm)) {
                Icon("magnifyingglass", tint: .neutral)
                TextInput(
                    DictionarySearch.label, value: query, placeholder: DictionarySearch.placeholder,
                    commitsWhileTyping: true
                ) { query = $0 }
            }
            SuggestedTermsCard(state, actions: actions, query: query)
            DictionaryEditor(state, actions: actions, query: query)
            ReplacementRulesEditor(state, actions: actions, query: query)
            SnippetsEditor(state, actions: actions, query: query)
            FillerRemovalCard(isOn: state.removesFillers, onChange: actions.removeFillers)
        }
    }
}

/// How the search of the Dictionary tab matches: a row is shown when one of its texts contains the search, with case and
/// accents ignored. An empty search shows every row.
nonisolated enum DictionarySearch {
    static func matches(_ query: String, _ texts: String...) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return texts.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static var label: String { L10n.string("dictionary.search", "Search the dictionary") }
    static var placeholder: String { L10n.string("dictionary.search.placeholder", "Search terms, rules, and snippets") }
    static var noMatches: String { L10n.string("dictionary.search.none", "Nothing matches the search.") }
}

#Preview("DictionaryTab") { PreviewMatrix { DictionaryTab.Gallery() } }
