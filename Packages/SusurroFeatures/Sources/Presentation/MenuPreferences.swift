import Domain
import Observation

/// The switches in the menu: clean up the text, use the app's context, use screen text, and command mode. Screen text
/// is the OCR controller, which also deals with the permission it needs; the others are plain settings.
@MainActor
@Observable
public final class MenuPreferences {
    public let ocr: OCRPreferenceController
    public private(set) var cleanupEnabled: Bool
    public private(set) var useAppContext: Bool
    public private(set) var commandMode: Bool

    @ObservationIgnored private let settings: any SettingsStore

    public init(settings: any SettingsStore, ocr: OCRPreferenceController) {
        self.settings = settings
        self.ocr = ocr
        cleanupEnabled = settings.value(for: CleanupSettings.enabled)
        useAppContext = settings.value(for: ContextSettings.useAppContext)
        commandMode = settings.value(for: CommandSettings.enabled)
    }

    /// The switches as the menu shows them. They read observable state, so a menu that reads them is drawn again when one
    /// changes.
    public var items: [MenuContent.Preference] {
        [
            MenuContent.Preference(
                kind: .cleanup, title: L10n.string("menu.preference.cleanup", "Clean up text (adds a few seconds)"),
                isOn: cleanupEnabled, note: nil),
            MenuContent.Preference(
                kind: .appContext, title: L10n.string("menu.preference.appContext", "Use app context"),
                isOn: useAppContext, note: nil),
            MenuContent.Preference(
                kind: .screenText, title: L10n.string("menu.preference.screenText", "Use screen text (OCR)"),
                isOn: ocr.isEnabled, note: ocr.explanation),
            MenuContent.Preference(
                kind: .commandMode,
                title: L10n.string("menu.preference.commandMode", "Command mode on the selection (adds seconds)"),
                isOn: commandMode, note: nil),
        ]
    }

    public func set(_ kind: MenuContent.Preference.Kind, to value: Bool) async {
        switch kind {
        case .cleanup:
            settings.set(value, for: CleanupSettings.enabled)
            cleanupEnabled = value
        case .appContext:
            settings.set(value, for: ContextSettings.useAppContext)
            useAppContext = value
        case .screenText:
            await ocr.setEnabled(value)
        case .commandMode:
            settings.set(value, for: CommandSettings.enabled)
            commandMode = value
        }
    }
}
