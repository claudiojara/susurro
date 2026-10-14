import DesignSystem
import SwiftUI

/// The settings: a bar of tabs and the tab in use. The window has the size the theme says and does not change from one
/// tab to the next, so a tab with more in it scrolls. A pure function of the state and the theme: what the controls do
/// is passed in, and the hotkey recorder, a native control, is a slot the app fills.
struct SettingsScreen<Recorder: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.staticControls) private var isStatic
    @State private var tab: SettingsTab
    private let state: SettingsViewState
    private let actions: SettingsActions
    private let recorder: Recorder

    init(
        state: SettingsViewState, actions: SettingsActions, tab: SettingsTab = .general,
        @ViewBuilder recorder: () -> Recorder
    ) {
        self.state = state
        self.actions = actions
        self.recorder = recorder()
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
            ChoiceChips(
                SettingsTab.allCases.map { SettingsChoice(id: $0.rawValue, title: $0.title) }, selected: tab.rawValue,
                label: "Settings sections"
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
        case .general: GeneralSection(state.general, actions: actions.general)
        case .providers: ProvidersSection(state.providers, actions: actions.providers)
        case .hotkey: HotkeySection(state.hotkey, actions: actions.hotkey) { recorder }
        case .style: StyleTableEditor(state.style, actions: actions.style)
        case .dictionary: DictionaryEditor(state.dictionary, actions: actions.dictionary)
        case .appearance: AppearanceSection(state.appearance, actions: actions.appearance)
        }
    }
}

#Preview("SettingsScreen") { PreviewMatrix { SettingsScreen<EmptyView>.Gallery() } }
