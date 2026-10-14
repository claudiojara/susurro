import DesignSystem
import Domain
import Observation
import SusurroUI

/// Adapts the settings of the app to the settings screen's contract. The settings store is the one place the values
/// live: every intent writes there and every read of `state` reads from there, so what the screen shows cannot drift from
/// what the rest of the app uses. A key is only ever asked about (`hasKey`); its value never gets here.
///
/// The extensions in the files next to this one hold the tabs: `+Providers`, `+Hotkey`, `+Style`, `+Appearance`.
@MainActor
@Observable
public final class SettingsViewModel: SettingsViewModeling {
    @ObservationIgnored let dependencies: SettingsDependencies
    @ObservationIgnored var settings: any SettingsStore { dependencies.settings }

    /// Counts the changes made to the settings, the style, and the dictionary. `state` reads it, so a view that reads
    /// `state` is drawn again after each of them, though the stores themselves are not observable.
    private var revision = 0
    /// How the local speech providers stand, by provider id, as the last `refresh()` read them.
    var readiness: [String: RecognizerReadiness] = [:]
    var appleIntelligenceAvailable: Bool?
    var inputMonitoring: PermissionStatus = .notDetermined
    var secureInputActive = false
    var themeIDs: [String] = [ThemeStore.defaultID]
    var overrideError: String?
    var dictionaryError: String?
    /// The last change of theme, which a test waits for.
    @ObservationIgnored var themeSelection: Task<Void, Never>?

    public init(_ dependencies: SettingsDependencies) {
        self.dependencies = dependencies
    }

    public var state: SettingsViewState {
        _ = revision
        return SettingsViewState(
            general: generalState,
            providers: providersState,
            hotkey: hotkeyState,
            style: styleState,
            dictionary: dictionaryState,
            appearance: appearanceState
        )
    }

    /// Follows the settings store, so that a setting changed elsewhere (the menu's toggles) shows, and reads the
    /// permission and Secure Event Input every second, until the task is cancelled.
    public func run() async {
        async let following: Void = followSettings()
        async let polling: Void = pollSystem()
        _ = await (following, polling)
    }

    private func followSettings() async {
        for await _ in settings.changes() { changed() }
    }

    private func pollSystem() async {
        while !Task.isCancelled {
            // The two values are observed properties, so a read that finds them as they were redraws nothing.
            await readSystem()
            try? await dependencies.clock.sleep(for: .seconds(1))
        }
    }

    private func readSystem() async {
        inputMonitoring = await dependencies.permissions.status(.inputMonitoring)
        secureInputActive = dependencies.secureInputActive()
    }

    /// Reads everything that can change without the screen's help.
    public func refresh() async {
        await readSystem()
        themeIDs = await dependencies.themes.themeIDs()
        appleIntelligenceAvailable = await dependencies.appleIntelligenceAvailable()
        for id in [ProviderID.parakeetV3, ProviderID.localWhisper] {
            readiness[id] = await dependencies.speechReadiness(id)
        }
        changed()
    }

    func changed() {
        revision &+= 1
    }

    // MARK: General

    private var generalState: GeneralSettingsState {
        let variants = dependencies.overlayVariants
        let storedVariant = settings.value(for: GeneralSettings.overlayVariant)
        let known = variants.contains { $0.id == storedVariant }
        return GeneralSettingsState(
            languages: SpeechLanguageMode.allCases.map {
                SettingsChoice(id: $0.rawValue, title: SettingsCopy.language($0))
            },
            selectedLanguage: settings.value(for: RecognitionSettings.languageMode).rawValue,
            appContextEnabled: settings.value(for: GeneralSettings.appContextEnabled),
            ocrEnabled: settings.value(for: GeneralSettings.ocrEnabled),
            cleanupEnabled: settings.value(for: CleanupSettings.enabled),
            overlayEdges: OverlayEdge.allCases.map { SettingsChoice(id: $0.rawValue, title: SettingsCopy.edge($0)) },
            selectedEdge: settings.value(for: GeneralSettings.overlayEdge).rawValue,
            overlayVariants: variants.map {
                SettingsChoice(
                    id: $0.id, title: $0.id == OverlayVariantOption.defaultID ? SettingsCopy.defaultTheme : $0.title)
            },
            selectedVariant: known ? storedVariant : OverlayVariantOption.defaultID,
            variantError: known ? nil : SettingsCopy.variantUnavailable(storedVariant),
            interfaceLanguages: InterfaceLanguage.allCases.map {
                SettingsChoice(id: $0.rawValue, title: SettingsCopy.interfaceLanguage($0))
            },
            selectedInterfaceLanguage: settings.value(for: GeneralSettings.interfaceLanguage).rawValue
        )
    }

    /// Stores the language of the app's own words and shows it at once. The dictation language is another setting.
    public func setInterfaceLanguage(_ id: String) {
        guard let language = InterfaceLanguage(rawValue: id) else { return }
        settings.set(language, for: GeneralSettings.interfaceLanguage)
        dependencies.interfaceLanguage(language)
        changed()
    }

    public func setLanguage(_ id: String) {
        guard let mode = SpeechLanguageMode(rawValue: id) else { return }
        settings.set(mode, for: RecognitionSettings.languageMode)
        changed()
    }

    public func setAppContext(_ isOn: Bool) {
        settings.set(isOn, for: GeneralSettings.appContextEnabled)
        changed()
    }

    public func setOCR(_ isOn: Bool) {
        settings.set(isOn, for: GeneralSettings.ocrEnabled)
        changed()
    }

    public func setCleanup(_ isOn: Bool) {
        settings.set(isOn, for: CleanupSettings.enabled)
        changed()
    }

    public func setOverlayEdge(_ id: String) {
        guard let edge = OverlayEdge(rawValue: id) else { return }
        settings.set(edge, for: GeneralSettings.overlayEdge)
        changed()
    }

    public func setOverlayVariant(_ id: String) {
        settings.set(id, for: GeneralSettings.overlayVariant)
        changed()
    }
}
