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
            SettingsCard(Copy.toneByCategory, footer: Copy.tableFooter) {
                ForEach(state.rows) { row in
                    VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                        HStack(spacing: theme.spacing(.sm)) {
                            TextLabel(row.title, style: .bodyEmphasized)
                            if row.isEdited { Pill(Copy.edited, tint: .accent) }
                        }
                        .accessibilityElement(children: .combine)
                        ChoiceChips(state.toneChoices, selected: row.toneID, label: Copy.tone(of: row.title)) {
                            actions.setTone(row.id, $0)
                        }
                    }
                }
            }
            SettingsCard(Copy.appsAndSites, footer: Copy.overrideFooter) {
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
                Icon("trash", tint: .error, label: Copy.remove(override.identifier))
            }
            .buttonStyle(.plain)
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
            TextLabel(Copy.addAnOverride, style: .bodyEmphasized)
            ChoiceChips(
                [SettingsChoice(id: "app", title: Copy.app), SettingsChoice(id: "site", title: Copy.site)],
                selected: isSite ? "site" : "app", label: Copy.overrideKind
            ) { isSite = $0 == "site" }
            TextInput(
                isSite ? Copy.website : Copy.bundleID, value: identifier,
                placeholder: isSite ? "mail.google.com" : "com.apple.Notes", commitsWhileTyping: true
            ) { identifier = $0 }
            if let error = state.overrideError { TextLabel(error, style: .caption, tint: .error) }
            TextLabel(Copy.optionalCategory, style: .caption, tint: .neutral)
            ChoiceChips(state.categoryChoices, selected: category ?? "", label: Copy.overrideCategory) {
                category = category == $0 ? nil : $0
            }
            TextLabel(Copy.optionalTone, style: .caption, tint: .neutral)
            ChoiceChips(state.toneChoices, selected: tone ?? "", label: Copy.overrideTone) {
                tone = tone == $0 ? nil : $0
            }
            ActionButton(Copy.addOverride, kind: .primary) {
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
        static var toneByCategory: String { L10n.string("style.toneByCategory", "Tone by category") }
        static var edited: String { L10n.string("style.edited", "Edited") }
        static var appsAndSites: String { L10n.string("style.appsAndSites", "Apps and sites") }
        static var addAnOverride: String { L10n.string("style.addAnOverride", "Add an override") }
        static var app: String { L10n.string("style.app", "App") }
        static var site: String { L10n.string("style.site", "Site") }
        static var overrideKind: String { L10n.string("style.overrideKind", "Override kind") }
        static var website: String { L10n.string("style.website", "Website") }
        static var bundleID: String { L10n.string("style.bundleID", "Bundle id") }
        static var optionalCategory: String { L10n.string("style.optionalCategory", "Category (optional)") }
        static var overrideCategory: String { L10n.string("style.overrideCategory", "Override category") }
        static var optionalTone: String { L10n.string("style.optionalTone", "Tone (optional)") }
        static var overrideTone: String { L10n.string("style.overrideTone", "Override tone") }
        static var addOverride: String { L10n.string("style.addOverride", "Add override") }
        static var tableFooter: String {
            L10n.string("style.tableFooter", "A category is picked from the app or the website you dictate into.")
        }
        static var overrideFooter: String {
            L10n.string(
                "style.overrideFooter",
                "An override changes the category, the tone, or both for one app (by its bundle id) or one site (by its host)."
            )
        }
        static var noOverrides: String { L10n.string("style.noOverrides", "No overrides yet.") }

        static func tone(of category: String) -> String { L10n.string("style.toneOf", "\(category) tone") }
        static func remove(_ identifier: String) -> String { L10n.string("style.remove", "Remove \(identifier)") }
    }
}

#Preview("StyleTableEditor") { PreviewMatrix { StyleTableEditor.Gallery() } }
