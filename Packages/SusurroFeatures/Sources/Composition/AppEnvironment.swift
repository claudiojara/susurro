import CoreTestSupport
import DesignSystem
import Domain
import Foundation
import Pipeline
import Presentation
import SusurroUI

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
            public var hotkey: @MainActor () -> HotkeyDescription
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
                hotkey: @escaping @MainActor () -> HotkeyDescription,
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
        /// Where each recording is written while it is captured, and read back from to be transcribed.
        public var recordings: any AudioRecordingStore
        public var recognizer: any SpeechRecognizer
        /// A new stream of the model's readiness on each call, starting with the current value.
        public var readinessChanges: @Sendable () async -> AsyncStream<RecognizerReadiness>
        public var inserter: any TextInserter
        public var permissions: any PermissionsChecker
        public var diagnostics: any DiagnosticsLog
        /// Makes the overlay on the screen, which shows the view model in the theme.
        public var overlay: @MainActor (OverlayViewModel, ThemeModel) -> any OverlaySurface
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
        /// The dictation history: where the records live, and what its screen, its retention job, and its retry use.
        public var history: HistoryDependencies
        /// Tells which app is in front as a dictation starts, so its text goes only to that app. Without it the text is
        /// pasted wherever the focus is when it is ready.
        public var frontmost: (any FrontmostAppProvider)?
        /// Captures the context of each dictation and chooses its style. Without it no context is captured.
        public var context: ContextPipeline?
        /// Finds the speech in a recording, so a silent one is not transcribed and the recognizer hears the voice with a
        /// little room on each side.
        public var vad: any VoiceActivityDetector
        /// Tells the language of a transcript, to notice one that came back in the wrong language.
        public var languageDetector: any LanguageDetecting
        /// A recognizer that honors the language it is asked for, to transcribe again a clip that the main one answered
        /// in the wrong language. Nil when the app has none.
        public var languageRecognizer: (any SpeechRecognizer)?
        /// The other recognizers the user can select, such as the cloud and local Whisper ones. A failure of one falls
        /// back to `recognizer`.
        public var otherRecognizers: [any SpeechRecognizer]
        /// Whether a cloud recognizer has its key. Without a key it cannot be used.
        public var credentials: any ProviderCredentials
        /// Cleans the transcript before it is inserted. Nil inserts the raw transcript.
        public var cleanup: CleanupStage?
        /// Builds the vocabulary of each dictation from the user's dictionary, the context, and the screen. Nil gives the
        /// recognizer and the cleaner no vocabulary.
        public var vocabulary: VocabularyPipeline?
        /// The settings window, or nil for a graph that has none.
        public var settingsScreen: SettingsScreen?

        public init(
            hotkeys: any HotkeySource,
            capture: any AudioCaptureSource,
            recordings: any AudioRecordingStore,
            recognizer: any SpeechRecognizer,
            readinessChanges: @escaping @Sendable () async -> AsyncStream<RecognizerReadiness>,
            inserter: any TextInserter,
            permissions: any PermissionsChecker,
            diagnostics: any DiagnosticsLog,
            overlay: @escaping @MainActor (OverlayViewModel, ThemeModel) -> any OverlaySurface,
            restoreClipboardNow: @escaping @MainActor () -> Void,
            settings: any SettingsStore,
            onboarding: Onboarding,
            theming: Theming,
            clock: any Clock<Duration> = ContinuousClock(),
            history: HistoryDependencies = .preview(),
            frontmost: (any FrontmostAppProvider)? = nil,
            context: ContextPipeline? = nil,
            vad: any VoiceActivityDetector = FakeVoiceActivityDetector(),
            languageDetector: any LanguageDetecting = FakeLanguageDetector(),
            languageRecognizer: (any SpeechRecognizer)? = nil,
            otherRecognizers: [any SpeechRecognizer] = [],
            credentials: any ProviderCredentials = NoProviderCredentials(),
            cleanup: CleanupStage? = nil,
            vocabulary: VocabularyPipeline? = nil,
            settingsScreen: SettingsScreen? = nil
        ) {
            self.hotkeys = hotkeys
            self.capture = capture
            self.recordings = recordings
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
            self.history = history
            self.frontmost = frontmost
            self.context = context
            self.vad = vad
            self.languageDetector = languageDetector
            self.languageRecognizer = languageRecognizer
            self.otherRecognizers = otherRecognizers
            self.credentials = credentials
            self.cleanup = cleanup
            self.vocabulary = vocabulary
            self.settingsScreen = settingsScreen
        }

        /// The recognizers of the app, as the registry and the runner take them.
        public var recognizerSet: RecognizerSet {
            RecognizerSet(
                main: recognizer, language: languageRecognizer, others: otherRecognizers, credentials: credentials)
        }

        /// What turns a clip into a raw transcript: the recognizers the app has, which of them is selected, the wait for
        /// a model that loads, the timeouts, the fallbacks, and the language guard. The dictation and the history's retry
        /// run the same one.
        public func recognitionRunner(
            sleep: @escaping @Sendable (Duration) async throws -> Void
        ) -> RecognitionRunner {
            Self.recognitionRunner(
                recognizers: recognizerSet, settings: settings, languageDetector: languageDetector,
                diagnostics: diagnostics, sleep: sleep)
        }

        /// The recognizers of the app: Parakeet, the default, the one that honors the language when there is one, and
        /// the others the user can select.
        public var recognizerRegistry: RecognizerRegistry {
            recognizerSet.registry(settings: settings)
        }

        static func recognitionRunner(
            recognizers: RecognizerSet, settings: any SettingsStore, languageDetector: any LanguageDetecting,
            diagnostics: any DiagnosticsLog, sleep: @escaping @Sendable (Duration) async throws -> Void
        ) -> RecognitionRunner {
            RecognitionRunner(
                registry: recognizers.registry(settings: settings),
                language: SettingsLanguagePreference(settings: settings),
                languageGuard: LanguageGuard(detector: languageDetector),
                diagnostics: diagnostics,
                sleep: sleep
            )
        }
    }

    /// The recognizers of the app and what decides whether a cloud one may be used.
    public struct RecognizerSet: Sendable {
        /// The default, which runs on this Mac and which a failure falls back to.
        public var main: any SpeechRecognizer
        /// The one that honors the language it is asked for.
        public var language: (any SpeechRecognizer)?
        public var others: [any SpeechRecognizer]
        public var credentials: any ProviderCredentials

        public init(
            main: any SpeechRecognizer, language: (any SpeechRecognizer)? = nil, others: [any SpeechRecognizer] = [],
            credentials: any ProviderCredentials = NoProviderCredentials()
        ) {
            self.main = main
            self.language = language
            self.others = others
            self.credentials = credentials
        }

        func registry(settings: any SettingsStore) -> RecognizerRegistry {
            RecognizerRegistry(
                providers: [main] + (language.map { [$0] } ?? []) + others,
                defaultProvider: main.id,
                languageProvider: language?.id,
                settings: settings,
                credentials: credentials
            )
        }
    }

    /// The state behind the menu bar menu, the one part of the graph the app reads.
    public let menu: MenuModel
    // The rest is internal: the tests read it, and the app does not need it.
    /// What the app knows about the permissions: the menu, the onboarding, and the overlay read it.
    let monitor: PermissionsMonitor
    /// The switches in the menu: cleanup, app context, and screen text.
    let preferences: MenuPreferences
    /// The onboarding screen's view model, over the monitor.
    let onboardingModel: OnboardingViewModel
    /// The theme the app's windows are drawn in, which follows the theme store.
    let themeModel: ThemeModel
    /// The history screen's view model, over the repository.
    let historyModel: HistoryViewModel
    /// What the overlay shows, over the pipeline's states.
    let overlayModel: OverlayViewModel
    /// The settings screen's view model, when the graph has a settings window.
    let settingsModel: SettingsViewModel?

    private let dependencies: Dependencies
    private let coordinator: DictationCoordinator
    private let watcher: ModelLoadWatcher
    private let onboardingPresenter: OnboardingPresenter
    private let retention: RetentionSweeper
    private var tasks: [Task<Void, Never>] = []
    private var hasStarted = false

    public init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        let clock = dependencies.clock
        let sleep: @Sendable (Duration) async throws -> Void = { try await clock.sleep(for: $0) }
        let pipeline = DictationPipeline(
            recordings: dependencies.recordings,
            history: dependencies.history.repository,
            detector: dependencies.vad,
            runner: dependencies.recognitionRunner(sleep: sleep),
            inserter: dependencies.inserter,
            cleanup: dependencies.cleanup,
            dates: dependencies.history.dates,
            diagnostics: dependencies.diagnostics,
            sleep: sleep
        )
        coordinator = DictationCoordinator(
            hotkeys: dependencies.hotkeys,
            capture: dependencies.capture,
            recordings: dependencies.recordings,
            recognizers: dependencies.recognizerRegistry,
            pipeline: pipeline,
            permissions: dependencies.permissions,
            frontmost: dependencies.frontmost,
            context: dependencies.context,
            diagnostics: dependencies.diagnostics,
            sleep: sleep,
            clock: clock,
            vocabulary: dependencies.vocabulary
        )
        themeModel = ThemeModel()
        let overlayModel = OverlayViewModel(sleep: sleep, uptime: OverlayViewModel.uptime(of: clock))
        let surface = dependencies.overlay(overlayModel, themeModel)
        overlayModel.display = { surface.display($0) }
        self.overlayModel = overlayModel
        watcher = ModelLoadWatcher(
            sleep: sleep, report: { overlayModel.setModelProgress($0) },
            reportUnavailable: { overlayModel.showModelUnavailable() })
        monitor = PermissionsMonitor(
            checker: dependencies.permissions, openSettings: dependencies.onboarding.openSettings, clock: clock,
            needs: PermissionNeeds(
                modifierOnlyHotkey: dependencies.settings.value(for: HotkeySettings.kind) == .modifierOnly),
            diagnostics: dependencies.diagnostics)
        onboardingModel = OnboardingViewModel(monitor: monitor)
        let onboardingPresenter = OnboardingPresenter(
            monitor: monitor, surface: dependencies.onboarding.window(onboardingModel, themeModel))
        self.onboardingPresenter = onboardingPresenter
        let history = dependencies.history
        historyModel = HistoryViewModel(
            repository: history.repository,
            actions: HistoryActions(
                repository: history.repository, deleter: history.deleter, clipboard: history.clipboard),
            retries: RetryService(
                repository: history.repository, loader: history.loader, reprocessor: history.reprocessor),
            dates: history.dates)
        retention = RetentionSweeper(
            repository: history.repository, deleter: history.deleter, dates: history.dates, clock: clock)
        let historyWindow = history.window(historyModel, themeModel)
        preferences = MenuPreferences(
            settings: dependencies.settings,
            ocr: OCRPreferenceController(settings: dependencies.settings, monitor: monitor))
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
            monitor: monitor, showOnboarding: { onboardingPresenter.show() }, showHistory: { historyWindow.show() },
            preferences: preferences, showSettings: showSettings)
    }

    /// Starts the app's work: the overlay, the hotkey, the model, the permission monitor and the onboarding, and the
    /// themes. It does nothing the second time.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let launchedAt = dependencies.history.dates.now()
        dependencies.diagnostics.record(.appLaunched)
        themeModel.appearance = dependencies.settings.value(for: AppearanceSettings.mode).override
        monitor.start()
        // The overlay listens before the coordinator can publish, and the coordinator registers the hotkey when it runs.
        run { await $0.overlayModel.run(states: $0.coordinator.states) }
        run { await $0.overlayModel.run(levels: $0.coordinator.levels) }
        run { await $0.overlayModel.follow($0.dependencies.settings) }
        run { await $0.coordinator.run() }
        run { await $0.watcher.run(await $0.dependencies.readinessChanges()) }
        run { await $0.menu.observe(await $0.dependencies.readinessChanges()) }
        run { await $0.logModelReadiness() }
        run { await $0.launch() }
        run { await $0.historyModel.run() }
        run { await $0.launchHistory(at: launchedAt) }
        run { await $0.onboardingPresenter.run() }
        run { await $0.monitor.run(activations: $0.dependencies.onboarding.activations()) }
        run { await $0.preferences.ocr.start() }
        run { await $0.followHotkeyKind() }
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

    /// A modifier-only or fn hotkey needs Input Monitoring, so the permissions the app asks for follow the hotkey the user
    /// chooses.
    private func followHotkeyKind() async {
        for await kind in dependencies.settings.values(for: HotkeySettings.kind) {
            var needs = monitor.needs
            needs.modifierOnlyHotkey = kind == .modifierOnly
            await monitor.setNeeds(needs)
        }
    }

    /// The model starts loading before the first press. The permissions are the monitor's and the onboarding's: the
    /// system prompts come when the user asks for a permission there, not at launch.
    private func launch() async {
        dependencies.diagnostics.record(.modelPrepareRequested)
        await dependencies.recognizer.prepare()
        await dependencies.languageRecognizer?.prepare()
    }

    /// The attempts that a quit left processing are marked failed, with their audio kept so they can be retried, and then
    /// the retention job runs: at once, and every 6 hours. Only attempts created before the launch are touched, so a
    /// dictation that begins as the app starts is left alone.
    private func launchHistory(at launch: Date) async {
        _ = try? await dependencies.history.repository.failInterrupted(createdBefore: launch)
        await retention.run()
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
