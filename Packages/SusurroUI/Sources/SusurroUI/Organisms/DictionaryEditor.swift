import DesignSystem
import SwiftUI

/// The words and names the user wants spelled as given. A term is edited in place and removed with the button beside it.
/// The field that adds a term keeps what the user is typing until Add is pressed. The list shows the terms that match the
/// search of the tab.
struct DictionaryEditor: View {
    @Environment(\.theme) private var theme
    private let state: DictionarySettingsState
    private let actions: DictionaryActions
    private let query: String
    @State private var newTerm = ""

    init(_ state: DictionarySettingsState, actions: DictionaryActions, query: String = "") {
        self.state = state
        self.actions = actions
        self.query = query
    }

    var body: some View {
        SettingsCard(Copy.title, footer: Copy.footer) {
            HStack(spacing: theme.spacing(.sm)) {
                TextInput(Copy.newTerm, value: newTerm, placeholder: Copy.placeholder, commitsWhileTyping: true) {
                    newTerm = $0
                }
                ActionButton(Copy.add, kind: .primary, action: add)
            }
            if let error = state.error { TextLabel(error, style: .caption, tint: .error) }
            if state.terms.isEmpty {
                TextLabel(Copy.empty, tint: .neutral)
            } else if terms.isEmpty {
                TextLabel(DictionarySearch.noMatches, tint: .neutral)
            }
            ForEach(terms, id: \.self) { term in
                HStack(spacing: theme.spacing(.sm)) {
                    TextInput(Copy.term, value: term) { actions.edit(term, $0) }
                    Button {
                        actions.remove(term)
                    } label: {
                        Icon("trash", tint: .error, label: Copy.remove(term))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var terms: [String] {
        state.terms.filter { DictionarySearch.matches(query, $0) }
    }

    private func add() {
        actions.add(newTerm)
        if !newTerm.trimmingCharacters(in: .whitespaces).isEmpty { newTerm = "" }
    }

    private enum Copy {
        static var title: String { L10n.string("dictionary.title", "Your words") }
        static var newTerm: String { L10n.string("dictionary.newTerm", "New term") }
        static var placeholder: String { L10n.string("dictionary.placeholder", "A name or a word") }
        static var add: String { L10n.string("dictionary.add", "Add") }
        static var term: String { L10n.string("dictionary.term", "Term") }
        static var footer: String {
            L10n.string(
                "dictionary.footer",
                "The speech model and the cleanup are asked to spell these terms as written. Nothing here is sent anywhere except to a cloud provider you turned on."
            )
        }
        static var empty: String { L10n.string("dictionary.empty", "No words yet.") }

        static func remove(_ term: String) -> String { L10n.string("dictionary.remove", "Remove \(term)") }
    }
}

#Preview("DictionaryEditor") { PreviewMatrix { DictionaryEditor.Gallery() } }
