import CoreTestSupport
import DesignSystem
import Domain
import Settings
import SusurroUI
import Synchronization

@testable import Presentation

/// Records the themes the view model picks, and lists the ones the test gives it.
final class FakeThemes: ThemeSelecting {
    private let state = Mutex((ids: [ThemeStore.defaultID], selected: [String]()))

    init(ids: [String] = [ThemeStore.defaultID, "ocean"]) {
        state.withLock { $0.ids = ids }
    }

    var selected: [String] { state.withLock { $0.selected } }

    func themeIDs() async -> [String] { state.withLock { $0.ids } }
    func select(_ id: String) async { state.withLock { $0.selected.append(id) } }
}

/// The answers of the system that the test changes while the view model runs.
final class SettingsKnobs: Sendable {
    private struct State {
        var keys: Set<SecretAccount> = []
        var hotkey = HotkeyDescription(keys: ["⌃", "⌥", "D"], isModifierOnly: false)
        var secureInput = false
        var readiness: [String: RecognizerReadiness] = [
            ProviderID.parakeetV3: .ready, ProviderID.localWhisper: .notInstalled,
        ]
        var appleIntelligence = true
        var problem: ExecutablePath.Problem? = .empty
    }

    private let state = Mutex(State())

    func setKey(_ account: SecretAccount, present: Bool) {
        state.withLock { if present { $0.keys.insert(account) } else { $0.keys.remove(account) } }
    }

    func hasKey(_ account: SecretAccount) -> Bool { state.withLock { $0.keys.contains(account) } }
    func setHotkey(_ hotkey: HotkeyDescription) { state.withLock { $0.hotkey = hotkey } }
    var hotkey: HotkeyDescription { state.withLock { $0.hotkey } }
    func setSecureInput(_ on: Bool) { state.withLock { $0.secureInput = on } }
    var secureInput: Bool { state.withLock { $0.secureInput } }
    func setReadiness(_ id: String, _ readiness: RecognizerReadiness) {
        state.withLock { $0.readiness[id] = readiness }
    }
    func readiness(_ id: String) -> RecognizerReadiness { state.withLock { $0.readiness[id] ?? .notInstalled } }
    func setAppleIntelligence(_ available: Bool) { state.withLock { $0.appleIntelligence = available } }
    var appleIntelligence: Bool { state.withLock { $0.appleIntelligence } }
    func setProblem(_ problem: ExecutablePath.Problem?) { state.withLock { $0.problem = problem } }
    var problem: ExecutablePath.Problem? { state.withLock { $0.problem } }
}

/// A settings view model over the real stores on an in-memory settings store, and the knobs for the rest.
@MainActor
struct SettingsRig {
    let settings = InMemorySettingsStore()
    let permissions = MutablePermissionsChecker()
    let knobs = SettingsKnobs()
    let themes = FakeThemes()
    let themeModel = ThemeModel()
    let variants = [
        OverlayVariantOption(id: OverlayVariantOption.defaultID, title: "Default"),
        OverlayVariantOption(id: "compact", title: "Compact"),
    ]

    func model(settings override: (any SettingsStore)? = nil) -> SettingsViewModel {
        let settings = override ?? self.settings
        let knobs = knobs
        return SettingsViewModel(
            SettingsDependencies(
                settings: settings,
                hasKey: { knobs.hasKey($0) },
                permissions: permissions,
                hotkey: { knobs.hotkey },
                secureInputActive: { knobs.secureInput },
                overlayVariants: variants,
                style: SettingsStylePreferences(settings: settings),
                dictionary: SettingsDictionaryTerms(settings: settings),
                speechReadiness: { knobs.readiness($0) },
                appleIntelligenceAvailable: { knobs.appleIntelligence },
                executableProblem: { _ in knobs.problem },
                themes: themes,
                themeModel: themeModel))
    }
}

extension SettingsViewState {
    func speech(_ id: String) -> ProviderRowState? { providers.speech.first { $0.id == id } }
    func cleanup(_ id: String) -> ProviderRowState? { providers.cleanup.first { $0.id == id } }
}

extension ProviderRowState {
    func field(_ id: String) -> ProviderFieldState? { fields.first { $0.id == id } }
}
