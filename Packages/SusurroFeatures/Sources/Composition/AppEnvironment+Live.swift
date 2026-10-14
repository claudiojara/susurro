import AppKit
import AudioIO
import Carbon.HIToolbox
import DesignSystem
import Diagnostics
import Domain
import FluidAudioASR
import Foundation
import Hotkeys
import LocalWhisper
import Permissions
import Presentation
import Secrets
import Settings
import SwiftUI
import TextInsertion

#if canImport(FoundationModels)
    import FoundationModels
#endif

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
        let settings = UserDefaultsSettingsStore(diagnostics: diagnostics)
        let themes = ThemeStore(directory: themesFolder, activeID: settings.value(for: AppearanceSettings.theme))
        return AppEnvironment.Dependencies(
            hotkeys: HotkeyService(),
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
            theming: Theming(store: themes, prepare: Self.prepareThemes(for: themes)),
            settingsScreen: settingsScreen(settings: settings, recognizer: recognizer, diagnostics: diagnostics)
        )
    }

    /// What the settings window reads from the system. The key store is the user's Keychain, asked only whether a key is
    /// there. The hotkey is the fixed default until it becomes configurable, and the recorder slot is empty for the same
    /// reason.
    @MainActor
    private static func settingsScreen(
        settings: any SettingsStore, recognizer: ParakeetRecognizer, diagnostics: any DiagnosticsLog
    ) -> SettingsScreen {
        let keys = KeychainSecretStore(diagnostics: diagnostics)
        return SettingsScreen(
            window: { SettingsWindowController(model: $0, themes: $1) },
            hasKey: { keys.hasSecret(for: $0) },
            hotkey: { HotkeyDescription(keys: ["⌃", "⌥", "D"], isModifierOnly: false) },
            secureInputActive: { IsSecureEventInputEnabled() },
            overlayVariants: [OverlayVariantOption(id: OverlayVariantOption.defaultID, title: "Default")],
            style: SettingsStylePreferences(settings: settings),
            dictionary: SettingsDictionaryTerms(settings: settings),
            speechReadiness: { id in
                switch id {
                case ProviderID.parakeetV3: await recognizer.readiness()
                case ProviderID.localWhisper: await LocalWhisperRecognizer(settings: settings).readiness()
                default: .notInstalled
                }
            },
            appleIntelligenceAvailable: { Self.appleIntelligenceIsAvailable }
        )
    }

    /// Whether Apple's on-device model can clean text on this Mac.
    private static var appleIntelligenceIsAvailable: Bool {
        #if canImport(FoundationModels)
            SystemLanguageModel.default.availability == .available
        #else
            false
        #endif
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
