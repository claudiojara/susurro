import CoreTestSupport
import DesignSystem
import Domain
import Foundation
import Presentation
import Synchronization
import Testing

@testable import Composition

/// An overlay that keeps what the presenter shows, in order.
@MainActor
final class SpyOverlay: OverlaySurface {
    private(set) var shown: [OverlayIndicator?] = []

    var messages: [String?] { shown.map { $0?.message } }
    var current: String? { shown.last.flatMap { $0 }?.message }

    func display(_ indicator: OverlayIndicator?) {
        shown.append(indicator)
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

/// The readiness the recognizer reports, to every subscriber, starting with the current value.
final class ReadinessFeed: Sendable {
    private let state = Mutex(
        (
            current: RecognizerReadiness.loading(progress: 0),
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
    let capture = FakeAudioCaptureSource()
    let recognizer: FakeRecognizer
    let inserter = FakeTextInserter()
    let permissions: MutablePermissionsChecker
    let diagnostics = RecordingDiagnostics()
    let sleeper = FakeSleeper()
    let overlay = SpyOverlay()
    let readiness = ReadinessFeed()
    let activations = AsyncStream.makeStream(of: Void.self)
    let clock = ManualClock()
    let settings = InMemorySettingsStore()
    let window = SpyOnboardingWindow()
    let themes: ThemeStore
    /// How many times the environment asked for the themes folder to be watched.
    let themeWatches = Counter()
    private let themeFolder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "susurro-themes-\(UUID().uuidString)")
    private(set) var openedSettings: [Permission] = []
    private(set) var clipboardRestores = 0
    private(set) var environment: AppEnvironment!

    /// - Parameter themeFiles: Theme files, by file name, that the themes folder holds when the environment is built.
    init(
        permissions: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted],
        recognizer: FakeRecognizer = FakeRecognizer(transcript: "hola"),
        themeFiles: [String: String] = [:]
    ) {
        self.permissions = MutablePermissionsChecker(permissions)
        self.recognizer = recognizer
        if !themeFiles.isEmpty {
            try? FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
            for (name, json) in themeFiles {
                try? Data(json.utf8).write(to: themeFolder.appendingPathComponent(name))
            }
        }
        themes = ThemeStore(directory: themeFolder)
        let readiness = readiness
        let activations = activations.stream
        let sleeper = sleeper
        let themeWatches = themeWatches
        let window = window
        environment = AppEnvironment(
            AppEnvironment.Dependencies(
                hotkeys: hotkeys,
                capture: capture,
                recognizer: recognizer,
                readinessChanges: { readiness.subscribe() },
                inserter: inserter,
                permissions: self.permissions,
                diagnostics: diagnostics,
                overlay: overlay,
                openSettings: { [unowned self] in openedSettings.append($0) },
                activations: { activations },
                restoreClipboardNow: { [unowned self] in clipboardRestores += 1 },
                onboardingWindow: { window.built(from: $0, $1) },
                settings: settings,
                themes: themes,
                watchThemes: { themeWatches.increment() },
                clock: clock,
                sleep: { try await sleeper.sleep($0) }
            )
        )
    }

    /// Removes the themes folder the test made.
    func removeThemeFolder() {
        try? FileManager.default.removeItem(at: themeFolder)
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
