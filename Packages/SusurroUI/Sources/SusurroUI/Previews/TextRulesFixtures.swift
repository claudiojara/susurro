import DesignSystem
import SwiftUI

// The states of the replacement rules, the snippets, and the filler switch, for the previews and the snapshot tests.
#if DEBUG

    extension SettingsFixtures {
        static let textRulesEmpty = DictionarySettingsState(terms: [], error: nil, removesFillers: false)
        static let textRules = DictionarySettingsState(
            terms: ["Acme"], error: nil,
            replacements: [
                ReplacementRowState(spoken: "jira", written: "Jira"),
                ReplacementRowState(spoken: "punto com", written: ".com"),
            ],
            replacementError: "That spoken form already has a rule.",
            snippets: [
                SnippetRowState(trigger: "mi firma", text: "Un saludo,\nClaudio Jara"),
                SnippetRowState(trigger: "dirección", text: "Calle Mayor 1, Madrid"),
            ],
            snippetError: nil, removesFillers: true)
    }

    extension DictionaryTab {
        struct Gallery: View {
            var body: some View {
                DictionaryTab(SettingsFixtures.textRules, actions: .none)
                    .environment(\.staticControls, true)
            }
        }
    }

    extension ReplacementRulesEditor {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    ReplacementRulesEditor(SettingsFixtures.textRulesEmpty, actions: .none)
                    ReplacementRulesEditor(SettingsFixtures.textRules, actions: .none)
                }
                .environment(\.staticControls, true)
            }
        }
    }

    extension SnippetsEditor {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    SnippetsEditor(SettingsFixtures.textRulesEmpty, actions: .none)
                    SnippetsEditor(SettingsFixtures.textRules, actions: .none)
                }
                .environment(\.staticControls, true)
            }
        }
    }

    extension FillerRemovalCard {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
                    FillerRemovalCard(isOn: true) { _ in }
                    FillerRemovalCard(isOn: false) { _ in }
                }
            }
        }
    }

#endif
