import DesignSystem
import SwiftUI

/// The voice snippets: a phrase and the text it inserts, which can span several lines. The trigger and the text are
/// edited in place, a snippet is removed with the button beside it, and the form at the top adds one when Add is pressed.
struct SnippetsEditor: View {
    @Environment(\.theme) private var theme
    private let state: DictionarySettingsState
    private let actions: DictionaryActions
    private let query: String
    @State private var trigger = ""
    @State private var text = ""

    init(_ state: DictionarySettingsState, actions: DictionaryActions, query: String = "") {
        self.state = state
        self.actions = actions
        self.query = query
    }

    var body: some View {
        SettingsCard(Copy.title, footer: Copy.footer) {
            VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
                TextInput(Copy.trigger, value: trigger, placeholder: Copy.triggerPlaceholder, commitsWhileTyping: true)
                {
                    trigger = $0
                }
                HStack(alignment: .top, spacing: theme.spacing(.sm)) {
                    TextInput(
                        Copy.text, value: text, placeholder: Copy.textPlaceholder, commitsWhileTyping: true,
                        isMultiline: true
                    ) { text = $0 }
                    ActionButton(Copy.add, kind: .primary, action: add)
                }
            }
            if let error = state.snippetError { TextLabel(error, style: .caption, tint: .error) }
            if state.snippets.isEmpty {
                TextLabel(Copy.empty, tint: .neutral)
            } else if rows.isEmpty {
                TextLabel(DictionarySearch.noMatches, tint: .neutral)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    HStack(spacing: theme.spacing(.sm)) {
                        TextInput(Copy.trigger, value: row.trigger) { actions.editSnippet(row.trigger, $0, row.text) }
                        Button {
                            actions.removeSnippet(row.trigger)
                        } label: {
                            Icon("trash", tint: .error, label: Copy.remove(row.trigger))
                        }
                        .buttonStyle(.plain)
                    }
                    TextInput(Copy.text, value: row.text, isMultiline: true) {
                        actions.editSnippet(row.trigger, row.trigger, $0)
                    }
                }
            }
        }
    }

    private var rows: [SnippetRowState] {
        state.snippets.filter { DictionarySearch.matches(query, $0.trigger, $0.text) }
    }

    private func add() {
        actions.addSnippet(trigger, text)
        let isComplete = [trigger, text].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if isComplete {
            trigger = ""
            text = ""
        }
    }

    private enum Copy {
        static var title: String { L10n.string("snippets.title", "Voice snippets") }
        static var trigger: String { L10n.string("snippets.trigger", "Trigger phrase") }
        static var triggerPlaceholder: String { L10n.string("snippets.trigger.placeholder", "What you say") }
        static var text: String { L10n.string("snippets.text", "Snippet text") }
        static var textPlaceholder: String { L10n.string("snippets.text.placeholder", "The text to insert") }
        static var add: String { L10n.string("snippets.add", "Add") }
        static var empty: String { L10n.string("snippets.empty", "No snippets yet.") }
        static var footer: String {
            L10n.string(
                "snippets.footer",
                "Say only the trigger to insert its text as written. A trigger of two words or more also works inside a longer dictation, and that dictation is not cleaned up. Option-Return starts a new line."
            )
        }

        static func remove(_ trigger: String) -> String { L10n.string("snippets.remove", "Remove \(trigger)") }
    }
}

#Preview("SnippetsEditor") { PreviewMatrix { SnippetsEditor.Gallery() } }
