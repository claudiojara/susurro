import CoreTestSupport
import Domain
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
    private(set) var openedSettings: [Permission] = []
    private(set) var clipboardRestores = 0
    private(set) var environment: AppEnvironment!

    init(
        permissions: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted],
        recognizer: FakeRecognizer = FakeRecognizer(transcript: "hola")
    ) {
        self.permissions = MutablePermissionsChecker(permissions)
        self.recognizer = recognizer
        let readiness = readiness
        let activations = activations.stream
        let sleeper = sleeper
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
                sleep: { try await sleeper.sleep($0) }
            )
        )
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
