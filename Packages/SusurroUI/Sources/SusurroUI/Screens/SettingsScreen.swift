import DesignSystem
import SwiftUI

/// The settings: a bar of tabs and the tab in use. The window has the size the theme says and does not change from one
/// tab to the next, so a tab with more in it scrolls. A pure function of the state and the theme: what the controls do
/// is passed in, and the hotkey recorder is a slot the app fills.
struct SettingsScreen<Recorder: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.staticControls) private var isStatic
    @State private var tab: SettingsTab
    private let state: SettingsViewState
    private let actions: SettingsActions
    private let recorder: Recorder
    /// The recorder of the shortcut that pastes the last dictation, a slot the app fills like `recorder`.
    private let pasteLastRecorder: AnyView

    init(
        state: SettingsViewState, actions: SettingsActions, tab: SettingsTab = .general,
        pasteLastRecorder: AnyView = AnyView(EmptyView()), @ViewBuilder recorder: () -> Recorder
    ) {
        self.state = state
        self.actions = actions
        self.recorder = recorder()
        self.pasteLastRecorder = pasteLastRecorder
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
            ChoiceChips(
                SettingsTab.allCases.map { SettingsChoice(id: $0.rawValue, title: $0.title) }, selected: tab.rawValue,
                label: L10n.string("settings.sections", "Settings sections")
            ) { tab = SettingsTab(rawValue: $0) ?? .general }
            if isStatic {
                // A snapshot cannot draw the inside of a scroll view, so it shows the top of the tab as it is.
                tabContent
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView { tabContent }
            }
        }
        .padding(theme.spacing(.xl))
        .frame(width: theme.layout(.settingsWidth), height: theme.layout(.settingsHeight), alignment: .topLeading)
        .background(theme.swiftUIColor(.surfaceWindow))
    }

    private var tabContent: some View {
        content.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general:
            VStack(spacing: theme.spacing(.md)) {
                GeneralSection(state.general, actions: actions.general)
                AudioSection(state.audio, actions: actions.audio)
            }
        case .providers: ProvidersSection(state.providers, actions: actions.providers)
        case .hotkey:
            VStack(spacing: theme.spacing(.md)) {
                HotkeySection(state.hotkey, actions: actions.hotkey) { recorder }
                PasteLastSection(state.pasteLast) { pasteLastRecorder }
            }
        case .style: StyleTableEditor(state.style, actions: actions.style)
        case .dictionary: DictionaryTab(state.dictionary, actions: actions.dictionary)
        case .appearance: AppearanceSection(state.appearance, actions: actions.appearance)
        }
    }
}

#Preview("SettingsScreen") { PreviewMatrix { SettingsScreen<EmptyView>.Gallery() } }
