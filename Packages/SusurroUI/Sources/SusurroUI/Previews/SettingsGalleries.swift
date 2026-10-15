import DesignSystem
import SwiftUI

// What the settings views look like, in one place: each gallery shows the states of one view. The previews draw these,
// and the snapshot tests draw the same fixtures one by one.
#if DEBUG

    extension ChoiceChips {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.md)) {
                    ChoiceChips(SettingsFixtures.languages, selected: "auto", label: "Language") { _ in }
                    ChoiceChips(SettingsFixtures.tones, selected: "casual", label: "Tone") { _ in }
                }
            }
        }
    }

    extension SettingsToggle {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.md)) {
                    SettingsToggle("Clean up text", detail: "Fixes punctuation and the tone.", isOn: true) { _ in }
                    SettingsToggle("Read text on screen (OCR)", isOn: false) { _ in }
                }
            }
        }
    }

    extension TextInput {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.md)) {
                    TextInput("Address", value: "http://127.0.0.1:8080/inference") { _ in }
                    TextInput("Model", value: "", placeholder: "whisper-1") { _ in }
                    TextInput("Address", value: "https://example.com", hasError: true) { _ in }
                }
                .environment(\.staticControls, true)
            }
        }
    }

    /// A card is generic over its content, so its gallery is a view of its own.
    struct SettingsCardGallery: View {
        var body: some View {
            SettingsCard("Overlay", footer: "Where the indicator appears.") {
                ChoiceChips(SettingsFixtures.edges, selected: "bottom", label: "Position") { _ in }
            }
        }
    }

    extension ShortcutBadge {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.md)) {
                    ShortcutBadge(["⌃", "⌥", "D"])
                    ShortcutBadge(["fn"])
                }
            }
        }
    }

    extension ProviderRow {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(spacing: theme.spacing(.sm)) {
                    ForEach(SettingsFixtures.Row.allCases, id: \.self) {
                        ProviderRow(SettingsFixtures.row($0), onSelect: {}, onEnable: { _ in }, onField: { _, _ in })
                    }
                }
                .environment(\.staticControls, true)
            }
        }
    }

    extension GeneralSection {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    GeneralSection(SettingsFixtures.general, actions: .none)
                    GeneralSection(SettingsFixtures.generalPinned, actions: .none)
                }
            }
        }
    }

    extension ProvidersSection {
        struct Gallery: View {
            var body: some View {
                ProvidersSection(SettingsFixtures.providers, actions: .none)
                    .environment(\.staticControls, true)
            }
        }
    }

    extension HotkeySection {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    HotkeySection<EmptyView>(SettingsFixtures.hotkey, actions: .none) { EmptyView() }
                    HotkeySection<EmptyView>(SettingsFixtures.hotkeyWarnings, actions: .none) { EmptyView() }
                }
            }
        }
    }

    extension AudioSection {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    AudioSection(SettingsFixtures.audio, actions: .none)
                    AudioSection(SettingsFixtures.audioMissing, actions: .none)
                }
            }
        }
    }

    extension PasteLastSection {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    PasteLastSection<HotkeyRecorder>(SettingsFixtures.pasteLast) {
                        HotkeyRecorder(state: SettingsFixtures.recorderPasteLast, actions: .none)
                    }
                    PasteLastSection<HotkeyRecorder>(SettingsFixtures.pasteLastUnassigned) {
                        HotkeyRecorder(state: SettingsFixtures.recorderIdle, actions: .none)
                    }
                }
            }
        }
    }

    extension CommandModeSection {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    CommandModeSection<EmptyView>(SettingsFixtures.commandMode, actions: .none) { EmptyView() }
                    CommandModeSection<EmptyView>(SettingsFixtures.commandModeUnavailable, actions: .none) {
                        EmptyView()
                    }
                }
            }
        }
    }

    extension HotkeyRecorder {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
                    HotkeyRecorder(state: SettingsFixtures.recorderIdle, actions: .none)
                    HotkeyRecorder(state: SettingsFixtures.recorderCustom, actions: .none)
                    HotkeyRecorder(state: SettingsFixtures.recorderListening, actions: .none)
                    HotkeyRecorder(state: SettingsFixtures.recorderHolding, actions: .none)
                    HotkeyRecorder(state: SettingsFixtures.recorderRefused, actions: .none)
                }
            }
        }
    }

    extension StyleTableEditor {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    StyleTableEditor(SettingsFixtures.style, actions: .none)
                    StyleTableEditor(SettingsFixtures.styleWithOverrides, actions: .none)
                }
                .environment(\.staticControls, true)
            }
        }
    }

    extension DictionaryEditor {
        struct Gallery: View {
            @Environment(\.theme) private var theme

            var body: some View {
                HStack(alignment: .top, spacing: theme.spacing(.lg)) {
                    DictionaryEditor(SettingsFixtures.dictionaryEmpty, actions: .none)
                    DictionaryEditor(SettingsFixtures.dictionary, actions: .none)
                }
                .environment(\.staticControls, true)
            }
        }
    }

    extension AppearanceSection {
        struct Gallery: View {
            var body: some View {
                AppearanceSection(SettingsFixtures.appearance, actions: .none)
            }
        }
    }

    extension SettingsScreen {
        struct Gallery: View {
            var body: some View {
                SettingsScreen<EmptyView>(state: SettingsFixtures.screen, actions: .none) { EmptyView() }
                    .environment(\.staticControls, true)
            }
        }
    }

    /// A model with a fixed state, for the preview of the container.
    @MainActor
    private final class PreviewSettingsModel: SettingsViewModeling {
        let state: SettingsViewState

        init(_ state: SettingsViewState) {
            self.state = state
        }

        func setLanguage(_ id: String) {}
        func setInterfaceLanguage(_ id: String) {}
        func setAppContext(_ isOn: Bool) {}
        func setOCR(_ isOn: Bool) {}
        func setCleanup(_ isOn: Bool) {}
        func setOverlayEdge(_ id: String) {}
        func setOverlayVariant(_ id: String) {}
        func selectProvider(_ id: String) {}
        func setProviderEnabled(_ id: String, isOn: Bool) {}
        func setProviderField(_ id: String, field: String, value: String) {}
        func requestInputMonitoring() async {}
        func setTone(category: String, tone: String) {}
        func addOverride(identifier: String, isSite: Bool, category: String?, tone: String?) {}
        func removeOverride(_ id: String) {}
        func addTerm(_ term: String) {}
        func editTerm(_ old: String, to new: String) {}
        func removeTerm(_ term: String) {}
        func addReplacement(spoken: String, written: String) {}
        func editReplacement(_ old: String, spoken: String, written: String) {}
        func removeReplacement(_ spoken: String) {}
        func addSnippet(trigger: String, text: String) {}
        func editSnippet(_ old: String, trigger: String, text: String) {}
        func removeSnippet(_ trigger: String) {}
        func setRemoveFillers(_ isOn: Bool) {}
        func selectTheme(_ id: String) {}
        func setAppearance(_ id: String) {}
        func selectMicrophone(_ id: String) {}
        func setPauseMedia(_ isOn: Bool) {}
        func refresh() async {}
        func run() async {}
    }

    #Preview("SettingsContainer") {
        PreviewMatrix {
            SettingsContainer(model: PreviewSettingsModel(SettingsFixtures.screen)) { EmptyView() }
        }
    }

#endif
