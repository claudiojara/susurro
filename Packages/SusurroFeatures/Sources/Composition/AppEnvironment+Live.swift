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
    /// The graph on the real adapters: the configured hotkey (Control+Option+D until the user changes it), the microphone, Parakeet, the pasteboard, the
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
        let settings = UserDefaultsSettingsStore(diagnostics: diagnostics)
        let themes = ThemeStore(directory: themesFolder)
        return AppEnvironment.Dependencies(
            hotkeys: HotkeyService(settings: settings, permissions: permissions),
            capture: AVAudioEngineCaptureSource(diagnostics: diagnostics),
            recognizer: recognizer,
            readinessChanges: { await recognizer.readinessChanges() },
            inserter: inserter,
            permissions: permissions,
            diagnostics: diagnostics,
            overlay: SkeletonOverlayController(),
            restoreClipboardNow: { inserter.restoreForTermination() },
            settings: settings,
            onboarding: Onboarding(
                window: { OnboardingWindowController(model: $0, themes: $1) },
                openSettings: { NSWorkspace.shared.open(permissions.settingsURL(for: $0)) },
                activations: Self.applicationActivations
            ),
            theming: Theming(store: themes, prepare: Self.prepareThemes(for: themes))
        )
    }

    /// Where the user puts theme files: `Themes` in the app's folder of Application Support.
    private static var themesFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Susurro/Themes", directoryHint: .isDirectory)
    }

    /// Creates the themes folder, empty, so that the user has a place to put a theme and the watcher has something to
    /// watch, and in debug builds starts the hot reload of the folder. The watcher is kept alive by the closure that
    /// starts it. The closure runs away from the main actor, since the folder is the user's and may be slow to answer.
    private static func prepareThemes(for themes: ThemeStore) -> @Sendable () async -> Void {
        let folder = themesFolder
        #if DEBUG
            let watcher = ThemeFileWatcher(directory: folder) { await themes.reload() }
            return {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                await watcher.start()
            }
        #else
            return { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
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
