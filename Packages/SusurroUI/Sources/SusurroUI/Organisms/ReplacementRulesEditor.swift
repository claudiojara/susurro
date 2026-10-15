import DesignSystem
import SwiftUI

/// The replacement rules: a spoken form and the way it is written ("jira" as "Jira"). Each form is edited in place, a rule
/// is removed with the button beside it, and the form at the top adds one when Add is pressed.
struct ReplacementRulesEditor: View {
    @Environment(\.theme) private var theme
    private let state: DictionarySettingsState
    private let actions: DictionaryActions
    private let query: String
    @State private var spoken = ""
    @State private var written = ""

    init(_ state: DictionarySettingsState, actions: DictionaryActions, query: String = "") {
        self.state = state
        self.actions = actions
        self.query = query
    }

    var body: some View {
        SettingsCard(Copy.title, footer: Copy.footer) {
            HStack(spacing: theme.spacing(.sm)) {
                TextInput(Copy.spoken, value: spoken, placeholder: Copy.spokenPlaceholder, commitsWhileTyping: true) {
                    spoken = $0
                }
                Icon("arrow.right", tint: .neutral)
                TextInput(Copy.written, value: written, placeholder: Copy.writtenPlaceholder, commitsWhileTyping: true)
                {
                    written = $0
                }
                ActionButton(Copy.add, kind: .primary, action: add)
            }
            if let error = state.replacementError { TextLabel(error, style: .caption, tint: .error) }
            if state.replacements.isEmpty {
                TextLabel(Copy.empty, tint: .neutral)
            } else if rows.isEmpty {
                TextLabel(DictionarySearch.noMatches, tint: .neutral)
            }
            ForEach(rows) { row in
                HStack(spacing: theme.spacing(.sm)) {
                    TextInput(Copy.spoken, value: row.spoken) { actions.editReplacement(row.spoken, $0, row.written) }
                    Icon("arrow.right", tint: .neutral)
                    TextInput(Copy.written, value: row.written) { actions.editReplacement(row.spoken, row.spoken, $0) }
                    Button {
                        actions.removeReplacement(row.spoken)
                    } label: {
                        Icon("trash", tint: .error, label: Copy.remove(row.spoken))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var rows: [ReplacementRowState] {
        state.replacements.filter { DictionarySearch.matches(query, $0.spoken, $0.written) }
    }

    private func add() {
        actions.addReplacement(spoken, written)
        let isComplete = [spoken, written].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if isComplete {
            spoken = ""
            written = ""
        }
    }

    private enum Copy {
        static var title: String { L10n.string("replacements.title", "Replacements") }
        static var spoken: String { L10n.string("replacements.spoken", "Spoken form") }
        static var spokenPlaceholder: String { L10n.string("replacements.spoken.placeholder", "What you say") }
        static var written: String { L10n.string("replacements.written", "Written form") }
        static var writtenPlaceholder: String { L10n.string("replacements.written.placeholder", "How it is written") }
        static var add: String { L10n.string("replacements.add", "Add") }
        static var empty: String { L10n.string("replacements.empty", "No replacements yet.") }
        static var footer: String {
            L10n.string(
                "replacements.footer",
                "Every dictation writes the spoken form as the written one, as whole words, whatever the case or accents. The written forms are also given to the speech model."
            )
        }

        static func remove(_ spoken: String) -> String { L10n.string("replacements.remove", "Remove \(spoken)") }
    }
}

#Preview("ReplacementRulesEditor") { PreviewMatrix { ReplacementRulesEditor.Gallery() } }
