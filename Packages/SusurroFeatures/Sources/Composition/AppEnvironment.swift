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
        public var hotkeys: any HotkeySource
        public var capture: any AudioCaptureSource
        public var recognizer: any SpeechRecognizer
        /// A new stream of the model's readiness on each call, starting with the current value.
        public var readinessChanges: @Sendable () async -> AsyncStream<RecognizerReadiness>
        public var inserter: any TextInserter
        public var permissions: any PermissionsChecker
        public var diagnostics: any DiagnosticsLog
        public var overlay: any OverlaySurface
        /// Opens the System Settings pane where the user changes a permission.
        public var openSettings: @MainActor (Permission) -> Void
        /// A value each time the app becomes the active app.
        public var activations: @Sendable () -> AsyncStream<Void>
        /// Puts the user's clipboard back at once if a paste is still under way. It runs as the app terminates.
        public var restoreClipboardNow: @MainActor () -> Void
        /// Paces every wait of the graph. Tests pass a fake.
        public var sleep: @Sendable (Duration) async throws -> Void

        public init(
            hotkeys: any HotkeySource,
            capture: any AudioCaptureSource,
            recognizer: any SpeechRecognizer,
            readinessChanges: @escaping @Sendable () async -> AsyncStream<RecognizerReadiness>,
            inserter: any TextInserter,
            permissions: any PermissionsChecker,
            diagnostics: any DiagnosticsLog,
            overlay: any OverlaySurface,
            openSettings: @escaping @MainActor (Permission) -> Void,
            activations: @escaping @Sendable () -> AsyncStream<Void>,
            restoreClipboardNow: @escaping @MainActor () -> Void,
            sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        ) {
            self.hotkeys = hotkeys
            self.capture = capture
            self.recognizer = recognizer
            self.readinessChanges = readinessChanges
            self.inserter = inserter
            self.permissions = permissions
            self.diagnostics = diagnostics
            self.overlay = overlay
            self.openSettings = openSettings
            self.activations = activations
            self.restoreClipboardNow = restoreClipboardNow
            self.sleep = sleep
        }
    }

    /// The state behind the menu bar menu.
    public let menu: MenuModel

    private let dependencies: Dependencies
    private let coordinator: DictationCoordinator
    private let presenter: SkeletonOverlayPresenter
    private let watcher: ModelLoadWatcher
    private let prompter: PermissionPrompter
    private var tasks: [Task<Void, Never>] = []
    private var hasStarted = false

    public init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        let sleep = dependencies.sleep
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
        prompter = PermissionPrompter(checker: dependencies.permissions)
        menu = MenuModel(
            permissions: dependencies.permissions,
            openSettings: dependencies.openSettings,
            sleep: sleep
        )
    }

    /// Starts the app's work: the overlay, the hotkey, the model, the permission prompts, and the menu. It does
    /// nothing the second time.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        dependencies.diagnostics.record(.appLaunched)
        // The overlay listens before the coordinator can publish, and the coordinator registers the hotkey when it runs.
        run { await $0.presenter.run(states: $0.coordinator.states) }
        run { await $0.coordinator.run() }
        run { await $0.watcher.run(await $0.dependencies.readinessChanges()) }
        run { await $0.menu.observe(await $0.dependencies.readinessChanges()) }
        run { await $0.logModelReadiness() }
        run { await $0.launch() }
        run { await $0.menu.keepRefreshing() }
        run { environment in
            for await _ in environment.dependencies.activations() { await environment.menu.refresh() }
        }
    }

    /// Stops the coordinator, which stops a recording and waits a moment for a paste to put the clipboard back, and
    /// then the rest. The app calls it when the user quits.
    public func shutdown() async {
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

    /// The model starts loading before the first press, then the permission prompts come one at a time, and then the
    /// menu reads what the user answered.
    private func launch() async {
        dependencies.diagnostics.record(.modelPrepareRequested)
        await dependencies.recognizer.prepare()
        await prompter.requestMissingPermissions()
        await menu.refresh()
        let microphone = await dependencies.permissions.status(.microphone)
        let accessibility = await dependencies.permissions.status(.accessibility)
        dependencies.diagnostics.record(
            .launchPermissions(microphone: Self.name(microphone), accessibility: Self.name(accessibility)))
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

    private static func name(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: "granted"
        case .denied: "denied"
        case .notDetermined: "notDetermined"
        }
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
