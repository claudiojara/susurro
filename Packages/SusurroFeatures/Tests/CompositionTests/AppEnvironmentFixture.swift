import CoreTestSupport
import DesignSystem
import Domain
import Foundation
import Pipeline
import Presentation
import SusurroUI
import Synchronization
import Testing

@testable import Composition

/// An overlay that keeps what the view model shows, in order.
@MainActor
final class SpyOverlay: OverlaySurface {
    private(set) var shown: [OverlayViewState] = []
    private(set) var model: OverlayViewModel?
    private(set) var themes: ThemeModel?

    var messages: [String?] { shown.map(\.text) }
    var current: String? { shown.last?.text }

    func display(_ state: OverlayViewState) {
        shown.append(state)
    }

    func built(from model: OverlayViewModel, _ themes: ThemeModel) -> SpyOverlay {
        self.model = model
        self.themes = themes
        return self
    }
}

/// An onboarding window that counts how many times it was shown, and keeps what it was built from.
@MainActor
final class SpyOnboardingWindow: OnboardingSurface {
    private(set) var shown = 0
    private(set) var model: OnboardingViewModel?
    private(set) var themes: ThemeModel?

    func show() { shown += 1 }

    func built(from model: OnboardingViewModel, _ themes: ThemeModel) -> SpyOnboardingWindow {
        self.model = model
        self.themes = themes
        return self
    }
}

/// Counts calls from code that is not on the main actor.
final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func increment() {
        count.withLock { $0 += 1 }
    }
}

/// The readiness the recognizer reports, to every subscriber, starting with the current value. The model is ready until
/// a test says otherwise, so that no timer of the model watcher shares the clock with the one a test is waiting for.
final class ReadinessFeed: Sendable {
    private let state = Mutex(
        (
            current: RecognizerReadiness.ready,
            subscribers: [AsyncStream<RecognizerReadiness>.Continuation]()
        ))

    func subscribe() -> AsyncStream<RecognizerReadiness> {
        let (stream, continuation) = AsyncStream.makeStream(of: RecognizerReadiness.self)
        state.withLock { state in
            continuation.yield(state.current)
            state.subscribers.append(continuation)
        }
        return stream
    }

    func publish(_ readiness: RecognizerReadiness) {
        let subscribers = state.withLock { state in
            state.current = readiness
            return state.subscribers
        }
        for subscriber in subscribers { subscriber.yield(readiness) }
    }
}

/// The app environment on fakes, with a handle on each of them.
@MainActor
final class AppEnvironmentFixture {
    let hotkeys = FakeHotkeySource()
    let capture: FakeAudioCaptureSource
    let recordings = FakeRecordingStore()
    let recognizer: FakeRecognizer
    let inserter = FakeTextInserter()
    let permissions: MutablePermissionsChecker
    let diagnostics = RecordingDiagnostics()
    let overlay = SpyOverlay()
    let readiness = ReadinessFeed()
    let activations = AsyncStream.makeStream(of: Void.self)
    /// The one clock of the graph: it paces the permission poll, the dictation limits, and the overlay.
    let clock = ManualClock()
    let settings = InMemorySettingsStore()
    let window = SpyOnboardingWindow()
    let themes: ThemeStore
    /// How many times the environment asked for the themes folder to be prepared and watched.
    let themePreparations = Counter()
    private let themeFolder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "susurro-themes-\(UUID().uuidString)")
    private(set) var openedSettings: [Permission] = []
    private(set) var clipboardRestores = 0
    /// The interface languages the app was told to show, in order.
    private(set) var appliedLanguages: [InterfaceLanguage] = []
    private(set) var environment: AppEnvironment!

    /// - Parameter themeFiles: Theme files, by file name, that the themes folder holds when the environment is built.
    init(
        permissions: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted],
        recognizer: FakeRecognizer = FakeRecognizer(transcript: "hola"),
        capture: FakeAudioCaptureSource = FakeAudioCaptureSource(),
        themeFiles: [String: String] = [:],
        history: HistoryDependencies = .preview(),
        settingsScreen: AppEnvironment.Dependencies.SettingsScreen? = nil,
        cleanup: CleanupStage? = nil
    ) {
        self.permissions = MutablePermissionsChecker(permissions)
        self.recognizer = recognizer
        self.capture = capture
        if !themeFiles.isEmpty {
            try? FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
            for (name, json) in themeFiles {
                try? Data(json.utf8).write(to: themeFolder.appendingPathComponent(name))
            }
        }
        themes = ThemeStore(directory: themeFolder)
        let readiness = readiness
        let activations = activations.stream
        let themePreparations = themePreparations
        let window = window
        environment = AppEnvironment(
            AppEnvironment.Dependencies(
                hotkeys: hotkeys,
                capture: capture,
                recordings: recordings,
                recognizer: recognizer,
                readinessChanges: { readiness.subscribe() },
                inserter: inserter,
                permissions: self.permissions,
                diagnostics: diagnostics,
                overlay: { [overlay] in overlay.built(from: $0, $1) },
                restoreClipboardNow: { [unowned self] in clipboardRestores += 1 },
                settings: settings,
                onboarding: AppEnvironment.Dependencies.Onboarding(
                    window: { window.built(from: $0, $1) },
                    openSettings: { [unowned self] in openedSettings.append($0) },
                    activations: { activations }
                ),
                theming: AppEnvironment.Dependencies.Theming(
                    store: themes, prepare: { themePreparations.increment() }),
                clock: clock,
                history: history,
                cleanup: cleanup,
                settingsScreen: settingsScreen,
                interfaceLanguage: { [unowned self] in appliedLanguages.append($0) }
            )
        )
    }

    /// Removes the themes folder the test made.
    func removeThemeFolder() {
        try? FileManager.default.removeItem(at: themeFolder)
    }

    /// Moves the clock by `duration` again and again until `condition` holds. A timer that the code under test has not
    /// started yet is started from the time now, so one advance can come too early; this does not depend on when the
    /// timer starts. It gives up after under a second of real time, which is less than the shortest real wait in the
    /// graph (the hold of an indicator is 1.2 s), so a timer that does not run on the clock cannot pass for one that does.
    func advance(
        by duration: Duration, until what: String, sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async {
        let giveUp = ContinuousClock.now + .milliseconds(800)
        while ContinuousClock.now < giveUp {
            if condition() { return }
            clock.advance(by: duration)
            try? await Task.sleep(for: .milliseconds(1))
        }
        if condition() { return }
        Issue.record("Timed out waiting for \(what).", sourceLocation: sourceLocation)
    }

    /// Waits until `condition` holds, polling for up to five seconds.
    func eventually(
        _ what: String, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
    ) async {
        for _ in 0..<5_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for \(what).", sourceLocation: sourceLocation)
    }
}
