import DesignSystem
import SwiftUI

/// The Appearance tab: the theme, from the bundled one and the files in the themes folder, and whether the windows follow
/// the system's light or dark or always use one. Both apply at once. A pure function of the state.
struct AppearanceSection: View {
    @Environment(\.theme) private var theme
    private let state: AppearanceSettingsState
    private let actions: AppearanceActions

    init(_ state: AppearanceSettingsState, actions: AppearanceActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: theme.spacing(.md)) {
            SettingsCard("Theme", footer: Copy.themeFooter) {
                ChoiceChips(state.themes, selected: state.selectedTheme, label: "Theme", onSelect: actions.theme)
                if let error = state.themeError { TextLabel(error, style: .caption, tint: .error) }
            }
            SettingsCard("Light or dark") {
                ChoiceChips(state.modes, selected: state.selectedMode, label: "Appearance", onSelect: actions.mode)
            }
        }
    }

    private enum Copy {
        static let themeFooter =
            "Put theme files in the Themes folder in Application Support/Susurro and they show up here."
    }
}

#Preview("AppearanceSection") { PreviewMatrix { AppearanceSection.Gallery() } }
