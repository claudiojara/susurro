import DesignSystem
import SwiftUI

/// The General tab: the language of the dictation, the switches for what the app reads and does with the text, and where
/// the overlay sits. A pure function of the state and the theme.
struct GeneralSection: View {
    @Environment(\.theme) private var theme
    private let state: GeneralSettingsState
    private let actions: GeneralActions

    init(_ state: GeneralSettingsState, actions: GeneralActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: theme.spacing(.md)) {
            SettingsCard("Language", footer: Copy.languageFooter) {
                ChoiceChips(
                    state.languages, selected: state.selectedLanguage, label: "Language", onSelect: actions.language)
            }
            SettingsCard("Text") {
                SettingsToggle(
                    "Clean up text", detail: "Fixes punctuation and matches the tone of the app you are in.",
                    isOn: state.cleanupEnabled, onChange: actions.cleanup)
                SettingsToggle(
                    "Use app context", detail: "Reads the app name and the text around the cursor to choose the tone.",
                    isOn: state.appContextEnabled, onChange: actions.appContext)
                SettingsToggle(
                    "Read text on screen (OCR)",
                    detail:
                        "Reads the window to spell names right. Needs Screen Recording. The text stays on this Mac.",
                    isOn: state.ocrEnabled, onChange: actions.ocr)
            }
            SettingsCard("Overlay") {
                labeled("Position") {
                    ChoiceChips(
                        state.overlayEdges, selected: state.selectedEdge, label: "Overlay position",
                        onSelect: actions.edge)
                }
                labeled("Style") {
                    ChoiceChips(
                        state.overlayVariants, selected: state.selectedVariant, label: "Overlay style",
                        onSelect: actions.variant)
                }
                if let error = state.variantError { TextLabel(error, style: .caption, tint: .error) }
            }
        }
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            TextLabel(title, style: .caption, tint: .neutral)
            content()
        }
    }

    private enum Copy {
        static let languageFooter =
            "Fast lets the speech model detect the language of each clip. Always Spanish asks for Spanish whenever the provider supports it."
    }
}

#Preview("GeneralSection") { PreviewMatrix { GeneralSection.Gallery() } }
