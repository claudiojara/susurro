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
            SettingsCard(Copy.interfaceLanguage, footer: Copy.interfaceLanguageFooter) {
                ChoiceChips(
                    state.interfaceLanguages, selected: state.selectedInterfaceLanguage, label: Copy.interfaceLanguage,
                    onSelect: actions.interfaceLanguage)
            }
            SettingsCard(Copy.language, footer: Copy.languageFooter) {
                ChoiceChips(
                    state.languages, selected: state.selectedLanguage, label: Copy.language, onSelect: actions.language)
            }
            SettingsCard(Copy.text) {
                SettingsToggle(
                    Copy.cleanup, detail: Copy.cleanupDetail,
                    isOn: state.cleanupEnabled, onChange: actions.cleanup)
                SettingsToggle(
                    Copy.appContext, detail: Copy.appContextDetail,
                    isOn: state.appContextEnabled, onChange: actions.appContext)
                SettingsToggle(
                    Copy.ocr, detail: Copy.ocrDetail,
                    isOn: state.ocrEnabled, onChange: actions.ocr)
            }
            SettingsCard(Copy.overlay, footer: Copy.overlayFooter) {
                labeled(Copy.position) {
                    ChoiceChips(
                        state.overlayEdges, selected: state.selectedEdge, label: Copy.overlayPosition,
                        onSelect: actions.edge)
                }
                labeled(Copy.style) {
                    ChoiceChips(
                        state.overlayVariants, selected: state.selectedVariant, label: Copy.overlayStyle,
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
        static var interfaceLanguage: String { L10n.string("general.interfaceLanguage", "Interface language") }
        static var interfaceLanguageFooter: String {
            L10n.string(
                "general.interfaceLanguageFooter",
                "The language of the menu, the windows, and the overlay. System follows the language of macOS. It does not change the language you dictate in."
            )
        }
        static var language: String { L10n.string("general.language", "Dictation language") }
        static var languageFooter: String {
            L10n.string(
                "general.languageFooter",
                "Fast lets the speech model detect the language of each clip. Always Spanish asks for Spanish whenever the provider supports it."
            )
        }
        static var text: String { L10n.string("general.text", "Text") }
        static var cleanup: String { L10n.string("general.cleanup", "Clean up text") }
        static var cleanupDetail: String {
            L10n.string("general.cleanupDetail", "Fixes punctuation and matches the tone of the app you are in.")
        }
        static var appContext: String { L10n.string("general.appContext", "Use app context") }
        static var appContextDetail: String {
            L10n.string(
                "general.appContextDetail", "Reads the app name and the text around the cursor to choose the tone.")
        }
        static var ocr: String { L10n.string("general.ocr", "Read text on screen (OCR)") }
        static var ocrDetail: String {
            L10n.string(
                "general.ocrDetail",
                "Reads the window to spell names right. Needs Screen Recording. The text stays on this Mac.")
        }
        static var overlay: String { L10n.string("general.overlay", "Overlay") }
        static var overlayFooter: String {
            L10n.string(
                "general.overlayFooter",
                "Live text shows your words as you speak. What is pasted is the final transcript, which can differ.")
        }
        static var position: String { L10n.string("general.position", "Position") }
        static var overlayPosition: String { L10n.string("general.overlayPosition", "Overlay position") }
        static var style: String { L10n.string("general.style", "Style") }
        static var overlayStyle: String { L10n.string("general.overlayStyle", "Overlay style") }
    }
}

#Preview("GeneralSection") { PreviewMatrix { GeneralSection.Gallery() } }
