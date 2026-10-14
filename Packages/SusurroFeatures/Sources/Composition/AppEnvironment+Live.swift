import AppKit
import AudioIO
import DesignSystem
import Diagnostics
import Domain
import FluidAudioASR
import Foundation
import Hotkeys
import Permissions
import Presentation
import Settings
import TextInsertion

extension AppEnvironment {
    /// The graph on the real adapters: the Control+Option+D hotkey, the microphone, Parakeet, the pasteboard, the
    /// system permissions, and the log. Build it once, at launch.
    public static var live: AppEnvironment {
        AppEnvironment(Dependencies.live())
    }
}

extension AppEnvironment.Dependencies {
    /// The real adapters. Touching them needs a microphone, the permissions, and the speech model, so this is covered
    /// by the manual check, not by tests.
    @MainActor
    static func live() -> AppEnvironment.Dependencies {
        let diagnostics = OSLogDiagnostics()
        let permissions = SystemPermissionsChecker()
        let recognizer = ParakeetRecognizer()
        let inserter = SimplePasteInserter(diagnostics: diagnostics)
        let themes = ThemeStore(directory: themesFolder)
        return AppEnvironment.Dependencies(
            hotkeys: HotkeyService(),
            capture: AVAudioEngineCaptureSource(diagnostics: diagnostics),
            recognizer: recognizer,
            readinessChanges: { await recognizer.readinessChanges() },
            inserter: inserter,
            permissions: permissions,
            diagnostics: diagnostics,
            overlay: SkeletonOverlayController(),
            openSettings: { NSWorkspace.shared.open(permissions.settingsURL(for: $0)) },
            activations: Self.applicationActivations,
            restoreClipboardNow: { inserter.restoreForTermination() },
            onboardingWindow: { OnboardingWindowController(model: $0, themes: $1) },
            settings: UserDefaultsSettingsStore(diagnostics: diagnostics),
            themes: themes,
            watchThemes: Self.themeWatcher(for: themes)
        )
    }

    /// Where the user puts theme files: `Themes` in the app's folder of Application Support.
    private static var themesFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Susurro/Themes", directoryHint: .isDirectory)
    }

    /// Hot reload of the themes folder, in debug builds. The watcher is kept alive by the closure that starts it.
    private static func themeWatcher(for themes: ThemeStore) -> @Sendable () async -> Void {
        #if DEBUG
            let watcher = ThemeFileWatcher(directory: themesFolder) { await themes.reload() }
            return { await watcher.start() }
        #else
            return {}
        #endif
    }

    /// A value each time the app becomes active, for as long as the stream is read.
    private static func applicationActivations() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let listening = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(
                    named: NSApplication.didBecomeActiveNotification)
                {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in listening.cancel() }
        }
    }
}
