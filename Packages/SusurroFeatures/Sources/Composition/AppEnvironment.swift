import DesignSystem
import Domain
import Pipeline
import Presentation

/// The dependency graph of the app, assembled once, and what the app does at launch and at quit. The ports of the core
/// package are the only things it knows about its parts, so the same graph runs on the live adapters (`live`) and on
/// the fakes (`preview`), and the tests run it on fakes they hold on to.
@MainActor
public final class AppEnvironment {
    /// The parts of the graph. `live()` and `preview()` build the two sets.
    public struct Dependencies {
        /// What the onboarding and the permissions monitor need from the system.
        public struct Onboarding {
            /// Makes the window of the onboarding, which shows the view model in the theme.
            public var window: @MainActor (OnboardingViewModel, ThemeModel) -> any OnboardingSurface
            /// Opens the System Settings pane where the user changes a permission.
            public var openSettings: @MainActor (Permission) -> Void
            /// A value each time the app becomes the active app.
            public var activations: @Sendable () -> AsyncStream<Void>

            public init(
                window: @escaping @MainActor (OnboardingViewModel, ThemeModel) -> any OnboardingSurface,
                openSettings: @escaping @MainActor (Permission) -> Void,
                activations: @escaping @Sendable () -> AsyncStream<Void>
            ) {
                self.window = window
                self.openSettings = openSettings
                self.activations = activations
            }
        }

        /// Where the app's themes come from.
        public struct Theming {
            /// The themes the user has put in the themes folder, and the one in use.
            public var store: ThemeStore
            /// Gets the themes folder ready and, in debug builds, starts watching it so an edited theme file shows at
            /// once. It runs once, at launch, away from the main actor.
            public var prepare: @Sendable () async -> Void

            public init(store: ThemeStore, prepare: @escaping @Sendable () async -> Void = {}) {
                self.store = store
                self.prepare = prepare
            }
        }

        /// What the settings window needs from the app, beyond what the rest of the graph already holds. A graph without it
        /// has no Settings item in the menu.
        public struct SettingsScreen {
            /// Makes the window of the settings, which shows the view model in the theme.
            public var window: @MainActor (SettingsViewModel, ThemeModel) -> any SettingsSurface
            /// Whether the key store has a key for the account. The key itself is never read for the settings.
            public var hasKey: @Sendable (SecretAccount) -> Bool
            public var hotkey: @Sendable () -> HotkeyDescription
            public var secureInputActive: @Sendable () -> Bool
            public var overlayVariants: [OverlayVariantOption]
            public var style: any StylePreferencesStore
            public var dictionary: any DictionaryTermStore
            /// How a local speech provider stands, by provider id.
            public var speechReadiness: @Sendable (String) async -> RecognizerReadiness
            public var appleIntelligenceAvailable: @Sendable () async -> Bool

            public init(
                window: @escaping @MainActor (SettingsViewModel, ThemeModel) -> any SettingsSurface,
                hasKey: @escaping @Sendable (SecretAccount) -> Bool,
                hotkey: @escaping @Sendable () -> HotkeyDescription,
                secureInputActive: @escaping @Sendable () -> Bool,
                overlayVariants: [OverlayVariantOption],
                style: any StylePreferencesStore,
                dictionary: any DictionaryTermStore,
                speechReadiness: @escaping @Sendable (String) async -> RecognizerReadiness,
                appleIntelligenceAvailable: @escaping @Sendable () async -> Bool
            ) {
                self.window = window
                self.hasKey = hasKey
                self.hotkey = hotkey
                self.secureInputActive = secureInputActive
                self.overlayVariants = overlayVariants
                self.style = style
                self.dictionary = dictionary
                self.speechReadiness = speechReadiness
                self.appleIntelligenceAvailable = appleIntelligenceAvailable
            }
        }

        public var hotkeys: any HotkeySource
        public var capture: any AudioCaptureSource
        public var recognizer: any SpeechRecognizer
        /// A new stream of the model's readiness on each call, starting with the current value.
        public var readinessChanges: @Sendable () async -> AsyncStream<RecognizerReadiness>
        public var inserter: any TextInserter
        public var permissions: any PermissionsChecker
        public var diagnostics: any DiagnosticsLog
        public var overlay: any OverlaySurface
        /// Puts the user's clipboard back at once if a paste is still under way. It runs as the app terminates.
        public var restoreClipboardNow: @MainActor () -> Void
        /// The user's settings. The graph holds them for the code that will read them: the first setting is read with the
        /// hotkey configuration.
        public var settings: any SettingsStore
        public var onboarding: Onboarding
        public var theming: Theming
        /// The one clock of the graph. It paces everything that waits: the permissions poll and the wait before the
        /// troubleshooting steps, the pauses and limits of a dictation, the time an overlay indicator stays, and the
        /// delay before the model's progress shows. Tests pass a `ManualClock`.
        public var clock: any Clock<Duration>
        /// The settings window, or nil for a graph that has none.
        public var settingsScreen: SettingsScreen?

        public init(
            hotkeys: any HotkeySource,
            capture: any AudioCaptureSource,
            recognizer: any SpeechRecognizer,
            readinessChanges: @escaping @Sendable () async -> AsyncStream<RecognizerReadiness>,
            inserter: any TextInserter,
            permissions: any PermissionsChecker,
            diagnostics: any DiagnosticsLog,
            overlay: any OverlaySurface,
            restoreClipboardNow: @escaping @MainActor () -> Void,
            settings: any SettingsStore,
            onboarding: Onboarding,
            theming: Theming,
            clock: any Clock<Duration> = ContinuousClock(),
            settingsScreen: SettingsScreen? = nil
        ) {
            self.hotkeys = hotkeys
            self.capture = capture
            self.recognizer = recognizer
            self.readinessChanges = readinessChanges
            self.inserter = inserter
            self.permissions = permissions
            self.diagnostics = diagnostics
            self.overlay = overlay
            self.restoreClipboardNow = restoreClipboardNow
            self.settings = settings
            self.onboarding = onboarding
            self.theming = theming
            self.clock = clock
            self.settingsScreen = settingsScreen
        }
    }

    /// The state behind the menu bar menu, the one part of the graph the app reads.
    public let menu: MenuModel
    // The rest is internal: the tests read it, and the app does not need it.
    /// What the app knows about the permissions: the menu, the onboarding, and the overlay read it.
    let monitor: PermissionsMonitor
    /// The onboarding screen's view model, over the monitor.
    let onboardingModel: OnboardingViewModel
    /// The theme the app's windows are drawn in, which follows the theme store.
    let themeModel: ThemeModel
    /// The settings screen's view model, when the graph has a settings window.
    let settingsModel: SettingsViewModel?

    private let dependencies: Dependencies
    private let coordinator: DictationCoordinator
    private let presenter: SkeletonOverlayPresenter
    private let watcher: ModelLoadWatcher
    private let onboardingPresenter: OnboardingPresenter
    private var tasks: [Task<Void, Never>] = []
    private var hasStarted = false

    public init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        let clock = dependencies.clock
        let sleep: @Sendable (Duration) async throws -> Void = { try await clock.sleep(for: $0) }
        coordinator = DictationCoordinator(
            hotkeys: dependencies.hotkeys,
            capture: dependencies.capture,
            recognizer: dependencies.recognizer,
            inserter: dependencies.inserter,
            permissions: dependencies.permissions,
            diagnostics: dependencies.diagnostics,
            sleep: sleep
        )
        let overlay = dependencies.overlay
        presenter = SkeletonOverlayPresenter(sleep: sleep, display: { overlay.display($0) })
        let presenter = presenter
        watcher = ModelLoadWatcher(
            sleep: sleep, report: { presenter.setModelProgress($0) },
            reportUnavailable: { presenter.showModelUnavailable() })
        monitor = PermissionsMonitor(
            checker: dependencies.permissions, openSettings: dependencies.onboarding.openSettings, clock: clock,
            diagnostics: dependencies.diagnostics)
        onboardingModel = OnboardingViewModel(monitor: monitor)
        themeModel = ThemeModel()
        let onboardingPresenter = OnboardingPresenter(
            monitor: monitor, surface: dependencies.onboarding.window(onboardingModel, themeModel))
        self.onboardingPresenter = onboardingPresenter
        var showSettings: (@MainActor () -> Void)?
        if let screen = dependencies.settingsScreen {
            let model = SettingsViewModel(
                SettingsDependencies(
                    settings: dependencies.settings, hasKey: screen.hasKey, permissions: dependencies.permissions,
                    hotkey: screen.hotkey, secureInputActive: screen.secureInputActive,
                    overlayVariants: screen.overlayVariants, style: screen.style, dictionary: screen.dictionary,
                    speechReadiness: screen.speechReadiness,
                    appleIntelligenceAvailable: screen.appleIntelligenceAvailable,
                    themes: dependencies.theming.store, themeModel: themeModel, clock: clock))
            let surface = screen.window(model, themeModel)
            settingsModel = model
            showSettings = { surface.show() }
        } else {
            settingsModel = nil
        }
        menu = MenuModel(
            monitor: monitor, showOnboarding: { onboardingPresenter.show() }, showSettings: showSettings)
    }

    /// Starts the app's work: the overlay, the hotkey, the model, the permission monitor and the onboarding, and the
    /// themes. It does nothing the second time.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        dependencies.diagnostics.record(.appLaunched)
        themeModel.appearance = dependencies.settings.value(for: AppearanceSettings.mode).override
        monitor.start()
        // The overlay listens before the coordinator can publish, and the coordinator registers the hotkey when it runs.
        run { await $0.presenter.run(states: $0.coordinator.states) }
        run { await $0.coordinator.run() }
        run { await $0.watcher.run(await $0.dependencies.readinessChanges()) }
        run { await $0.menu.observe(await $0.dependencies.readinessChanges()) }
        run { await $0.logModelReadiness() }
        run { await $0.launch() }
        run { await $0.onboardingPresenter.run() }
        run { await $0.monitor.run(activations: $0.dependencies.onboarding.activations()) }
        run { await $0.themeModel.follow(await $0.dependencies.theming.store.updates()) }
        // The folder is read away from the main actor, so a slow disk or a link to a volume that is not there cannot hold
        // the launch up. The bundled theme shows until the files are known.
        run { await $0.dependencies.theming.store.reload() }
        run { await $0.dependencies.theming.prepare() }
    }

    /// Stops the permission poll and the coordinator, which stops a recording and waits a moment for a paste to put the
    /// clipboard back, and then the rest. The app calls it when the user quits.
    public func shutdown() async {
        monitor.stop()
        await coordinator.shutdown()
        for task in tasks { task.cancel() }
        tasks = []
    }

    /// What the app does as it terminates, after the shutdown: it logs that it is terminating, and as a last resort, if a
    /// paste is still under way, the user's clipboard goes back synchronously.
    public func willTerminate() {
        dependencies.diagnostics.record(.appTerminating)
        dependencies.restoreClipboardNow()
    }

    // MARK: Launch

    /// The model starts loading before the first press. The permissions are the monitor's and the onboarding's: the
    /// system prompts come when the user asks for a permission there, not at launch.
    private func launch() async {
        dependencies.diagnostics.record(.modelPrepareRequested)
        await dependencies.recognizer.prepare()
    }

    private func logModelReadiness() async {
        var last: String?
        for await readiness in await dependencies.readinessChanges() {
            let name = Self.name(readiness)
            guard name != last else { continue }
            last = name
            dependencies.diagnostics.record(.modelReadiness(name))
        }
    }

    private func run(_ work: @escaping @MainActor (AppEnvironment) async -> Void) {
        tasks.append(Task { await work(self) })
    }

    private static func name(_ readiness: RecognizerReadiness) -> String {
        switch readiness {
        case .loading: "loading"
        case .ready: "ready"
        case .unavailable: "unavailable"
        case .notInstalled: "notInstalled"
        }
    }
}
