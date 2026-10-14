import DesignSystem
import SwiftUI

/// The Style tab: the tone of each category, and the overrides for single apps and sites. The form that adds an override
/// keeps what the user is typing until Add is pressed. Everything else is a pure function of the state.
struct StyleTableEditor: View {
    @Environment(\.theme) private var theme
    private let state: StyleSettingsState
    private let actions: StyleActions

    @State private var isSite = false
    @State private var identifier = ""
    @State private var category: String?
    @State private var tone: String?

    init(_ state: StyleSettingsState, actions: StyleActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: theme.spacing(.md)) {
            SettingsCard("Tone by category", footer: Copy.tableFooter) {
                ForEach(state.rows) { row in
                    VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                        HStack(spacing: theme.spacing(.sm)) {
                            TextLabel(row.title, style: .bodyEmphasized)
                            if row.isEdited { Pill("Edited", tint: .accent) }
                        }
                        .accessibilityElement(children: .combine)
                        ChoiceChips(state.toneChoices, selected: row.toneID, label: "\(row.title) tone") {
                            actions.setTone(row.id, $0)
                        }
                    }
                }
            }
            SettingsCard("Apps and sites", footer: Copy.overrideFooter) {
                if state.overrides.isEmpty {
                    TextLabel(Copy.noOverrides, tint: .neutral)
                }
                ForEach(state.overrides) { override in
                    overrideRow(override)
                }
                addForm
            }
        }
    }

    private func overrideRow(_ override: StyleOverrideRowState) -> some View {
        HStack(spacing: theme.spacing(.sm)) {
            Pill(override.kind)
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                TextLabel(override.identifier, style: .bodyEmphasized)
                TextLabel(override.summary, style: .caption, tint: .neutral)
            }
            Spacer(minLength: theme.spacing(.sm))
            Button {
                actions.removeOverride(override.id)
            } label: {
                Icon("trash", tint: .error, label: "Remove \(override.identifier)")
            }
            .buttonStyle(.plain)
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
            TextLabel("Add an override", style: .bodyEmphasized)
            ChoiceChips(
                [SettingsChoice(id: "app", title: "App"), SettingsChoice(id: "site", title: "Site")],
                selected: isSite ? "site" : "app", label: "Override kind"
            ) { isSite = $0 == "site" }
            TextInput(
                isSite ? "Website" : "Bundle id", value: identifier,
                placeholder: isSite ? "mail.google.com" : "com.apple.Notes", commitsWhileTyping: true
            ) { identifier = $0 }
            if let error = state.overrideError { TextLabel(error, style: .caption, tint: .error) }
            TextLabel("Category (optional)", style: .caption, tint: .neutral)
            ChoiceChips(state.categoryChoices, selected: category ?? "", label: "Override category") {
                category = category == $0 ? nil : $0
            }
            TextLabel("Tone (optional)", style: .caption, tint: .neutral)
            ChoiceChips(state.toneChoices, selected: tone ?? "", label: "Override tone") {
                tone = tone == $0 ? nil : $0
            }
            ActionButton("Add override", kind: .primary) {
                actions.addOverride(identifier, isSite, category, tone)
                // A form that the view model refuses keeps what was typed, so the user can fix it.
                let isComplete =
                    !identifier.trimmingCharacters(in: .whitespaces).isEmpty && (category != nil || tone != nil)
                if isComplete {
                    identifier = ""
                    category = nil
                    tone = nil
                }
            }
        }
    }

    private enum Copy {
        static let tableFooter = "A category is picked from the app or the website you dictate into."
        static let overrideFooter =
            "An override changes the category, the tone, or both for one app (by its bundle id) or one site (by its host)."
        static let noOverrides = "No overrides yet."
    }
}

#Preview("StyleTableEditor") { PreviewMatrix { StyleTableEditor.Gallery() } }
