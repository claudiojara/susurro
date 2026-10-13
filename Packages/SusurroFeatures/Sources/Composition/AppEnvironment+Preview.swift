import CoreTestSupport
import Domain
import Presentation

extension AppEnvironment {
    /// The graph on the fakes, for previews and for running the app without a microphone or a model.
    public static var preview: AppEnvironment {
        AppEnvironment(Dependencies.preview())
    }
}

extension AppEnvironment.Dependencies {
    /// Fakes with every permission granted and the model ready. The hotkey never fires.
    public static func preview(transcript: String = "Preview dictation") -> AppEnvironment.Dependencies {
        AppEnvironment.Dependencies(
            hotkeys: FakeHotkeySource(),
            capture: FakeAudioCaptureSource(),
            recognizer: FakeRecognizer(transcript: transcript),
            readinessChanges: { AsyncStream { $0.yield(.ready) } },
            inserter: FakeTextInserter(),
            permissions: FakePermissionsChecker([.microphone: .granted, .accessibility: .granted]),
            diagnostics: NoDiagnostics(),
            overlay: NoOverlay(),
            openSettings: { _ in },
            activations: { AsyncStream { _ in } },
            restoreClipboardNow: {}
        )
    }
}

/// An overlay that shows nothing.
@MainActor
private struct NoOverlay: OverlaySurface {
    func display(_ indicator: OverlayIndicator?) {}
}
