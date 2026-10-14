import CoreTestSupport
import DesignSystem
import Domain
import Presentation
import Settings
import Testing

@testable import Composition

/// A settings window that counts how many times it was shown, and keeps what it was built from.
@MainActor
final class SpySettingsWindow: SettingsSurface {
    private(set) var shown = 0
    private(set) var model: SettingsViewModel?
    private(set) var themes: ThemeModel?

    func show() { shown += 1 }

    func built(from model: SettingsViewModel, _ themes: ThemeModel) -> SpySettingsWindow {
        self.model = model
        self.themes = themes
        return self
    }
}

@MainActor
@Suite("Settings wiring", .timeLimit(.minutes(1)))
struct SettingsWiringTests {
    private func screen(
        window: SpySettingsWindow, settings: any SettingsStore
    ) -> AppEnvironment.Dependencies.SettingsScreen {
        AppEnvironment.Dependencies.SettingsScreen(
            window: { window.built(from: $0, $1) },
            hasKey: { _ in false },
            hotkey: { HotkeyDescription(keys: ["⌃", "⌥", "D"], isModifierOnly: false) },
            secureInputActive: { false },
            overlayVariants: [OverlayVariantOption(id: OverlayVariantOption.defaultID, title: "Default")],
            style: StyleSettingsRepository(store: settings),
            dictionary: DictionaryStore(settings: settings),
            speechReadiness: { _ in .ready },
            appleIntelligenceAvailable: { true })
    }

    @Test("a graph without a settings window has no Settings item in the menu")
    func noSettings() {
        let f = AppEnvironmentFixture()

        #expect(!f.environment.menu.hasSettings)
        #expect(f.environment.settingsModel == nil)
    }

    @Test("the Settings item of the menu opens the settings window, built over the graph's own settings and theme")
    func menuOpensSettings() {
        let window = SpySettingsWindow()
        let settings = InMemorySettingsStore()
        let f = AppEnvironmentFixture(settingsScreen: screen(window: window, settings: settings))

        #expect(f.environment.menu.hasSettings)
        f.environment.menu.openSettingsWindow()
        f.environment.menu.openSettingsWindow()

        #expect(window.shown == 2)
        #expect(window.model === f.environment.settingsModel)
        #expect(window.themes === f.environment.themeModel)
    }

    @Test("the settings screen shows what the graph's settings store holds")
    func sharesTheStore() {
        let window = SpySettingsWindow()
        let f = AppEnvironmentFixture(settingsScreen: screen(window: window, settings: InMemorySettingsStore()))
        f.settings.set(true, for: CleanupSettings.enabled)

        #expect(f.environment.settingsModel?.state.general.cleanupEnabled == true)
    }

    @Test("the interface language the user chose is applied at launch, and a pick in the settings is applied at once")
    func interfaceLanguage() async {
        let settings = InMemorySettingsStore()
        let f = AppEnvironmentFixture(settingsScreen: screen(window: SpySettingsWindow(), settings: settings))
        f.settings.set(.spanish, for: GeneralSettings.interfaceLanguage)

        f.environment.start()
        #expect(f.appliedLanguages == [.spanish])

        f.environment.settingsModel?.setInterfaceLanguage("en")
        #expect(f.appliedLanguages == [.spanish, .english])
        await f.environment.shutdown()
    }

    @Test("the appearance the user chose is applied at launch, without opening the settings")
    func appearanceAtLaunch() async {
        let f = AppEnvironmentFixture()
        f.settings.set(.dark, for: AppearanceSettings.mode)

        f.environment.start()

        #expect(f.environment.themeModel.appearance == .dark)
        await f.environment.shutdown()
    }
}
