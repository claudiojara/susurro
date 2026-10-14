import AccessibilityContext
import AppKit
import AppleIntelligenceCleaner
import AppleSpeechASR
import AudioIO
import Carbon.HIToolbox
import CloudProviders
import DesignSystem
import Diagnostics
import Domain
import EntityTagging
import FluidAudioASR
import Foundation
import Hotkeys
import LanguageDetection
import LocalWhisper
import Permissions
import Pipeline
import Presentation
import ScreenOCR
import Secrets
import Settings
import SusurroUI
import SwiftUI
import TextInsertion
import TextShaping

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension AppEnvironment {
    /// The graph on the real adapters: the configured hotkey (Control+Option+D until the user changes it), the
    /// microphone, Parakeet, the pasteboard, the system permissions, and the log. Build it once, at launch.
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
        let frontmost = NSWorkspaceFrontmostAppProvider()
        let inserter = PasteTransaction(
            pasteboard: NSPasteboardAdapter(), keystrokes: CGEventKeystrokePoster(), frontmost: frontmost,
            diagnostics: diagnostics)
        let clock = ContinuousClock()
        let settings = UserDefaultsSettingsStore(diagnostics: diagnostics)
        let themes = ThemeStore(directory: themesFolder, activeID: settings.value(for: AppearanceSettings.theme))
        let vad = SileroVADDetector()
        let languageDetector = NLLanguageDetector()
        let languageRecognizer = AppleSpeechRecognizer()
        let sleep: @Sendable (Duration) async throws -> Void = { try await clock.sleep(for: $0) }
        // The keys of the cloud providers are only looked up, in the external Keychain service (ADR 0003).
        let keys = KeychainSecretStore(diagnostics: diagnostics)
        // Deepgram and local Whisper can be selected; a failure of either falls back to Parakeet.
        let recognizers = AppEnvironment.RecognizerSet(
            main: recognizer, language: languageRecognizer,
            others: [
                DeepgramRecognizer(settings: settings, secrets: keys, diagnostics: diagnostics),
                LocalWhisperRecognizer(settings: settings),
            ],
            credentials: KeychainProviderCredentials(keys: keys))
        // The history's retry runs the same recognition as a new dictation, from the stored file to the raw text.
        let reprocessor = PipelineReprocessor(
            detector: vad,
            runner: AppEnvironment.Dependencies.recognitionRunner(
                recognizers: recognizers, settings: settings, languageDetector: languageDetector,
                diagnostics: diagnostics, sleep: sleep))
        let cleanup = CleanupStage(
            settings: settings,
            registry: CleanerRegistry(
                settings: settings,
                entries: [
                    .local(AppleIntelligenceCleaner()),
                    .cloud(
                        AnthropicCleaner(settings: settings, secrets: keys, diagnostics: diagnostics),
                        isEnabled: { settings.value(for: CleanupSettings.anthropicEnabled) },
                        hasKey: { keys.hasSecret(for: .anthropic) }),
                    .cloud(
                        OpenAICompatibleCleaner(settings: settings, secrets: keys, diagnostics: diagnostics),
                        isEnabled: { settings.value(for: CleanupSettings.openAICompatibleEnabled) },
                        hasKey: { keys.hasSecret(for: .openAICompatible) }),
                ]),
            sleep: sleep)
        let vocabulary = VocabularyPipeline(
            dictionary: DictionaryStore(settings: settings),
            builder: VocabularyBuilder(tagger: NLTaggerEntityTagger()),
            enrichment: ContextEnrichment(
                settings: settings, permissions: permissions,
                recognizer: VisionScreenTextRecognizer(images: ScreenCaptureWindowImageProvider()),
                frontmost: { await MainActor.run { frontmost.current().map { ScreenTarget(app: $0) } } }))
        return AppEnvironment.Dependencies(
            hotkeys: HotkeyService(settings: settings, permissions: permissions),
            capture: AVAudioEngineCaptureSource(diagnostics: diagnostics),
            recordings: CAFRecordingStore(directory: { Self.recordingsFolder }, diagnostics: diagnostics),
            recognizer: recognizer,
            readinessChanges: { await recognizer.readinessChanges() },
            inserter: inserter,
            permissions: permissions,
            diagnostics: diagnostics,
            overlay: { OverlayController(model: $0, themes: $1, registry: .standard()) },
            restoreClipboardNow: { inserter.restoreForTermination() },
            settings: settings,
            onboarding: Onboarding(
                window: { OnboardingWindowController(model: $0, themes: $1) },
                openSettings: { NSWorkspace.shared.open(permissions.settingsURL(for: $0)) },
                activations: Self.applicationActivations
            ),
            theming: Theming(store: themes, prepare: Self.prepareThemes(for: themes)),
            clock: clock,
            history: .live(reprocessor: reprocessor),
            frontmost: frontmost,
            context: Self.contextPipeline(settings: settings),
            vad: vad,
            languageDetector: languageDetector,
            languageRecognizer: languageRecognizer,
            otherRecognizers: recognizers.others,
            credentials: recognizers.credentials,
            cleanup: cleanup,
            vocabulary: vocabulary,
            settingsScreen: settingsScreen(settings: settings, recognizer: recognizer, diagnostics: diagnostics),
            interfaceLanguage: { $0.apply() }
        )
    }

    /// The text around the cursor is read through Accessibility, the style is chosen from the app and the page with the
    /// user's style settings, and the setting "use app context" decides whether the text is read at all.
    private static func contextPipeline(settings: UserDefaultsSettingsStore) -> ContextPipeline {
        let resolver = StyleResolver()
        let styles = StyleSettingsRepository(store: settings)
        return ContextPipeline(
            source: ContextCapture(
                reader: AXContextReader(), useAppContext: { settings.value(for: ContextSettings.useAppContext) }),
            resolver: resolver,
            styleSettings: { bundleID, url in
                styles.settings(for: resolver.candidateTargets(bundleID: bundleID, url: url))
            })
    }

    /// Where the recordings are kept: `Audio` in the app's folder of Application Support.
    private static var recordingsFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Susurro/Audio", directoryHint: .isDirectory)
    }

    /// What the settings window reads from the system. The key store is the user's Keychain, asked only whether a key is
    /// there. The hotkey shown is the configured one (`HotkeySettings`), and the Hotkey tab changes it with the recorder:
    /// the keys come from the app's own events (`NSEventHotkeyCaptureSource`) and the shortcuts that System Settings has
    /// turned on are refused (`SystemShortcuts`).
    @MainActor
    private static func settingsScreen(
        settings: any SettingsStore, recognizer: ParakeetRecognizer, diagnostics: any DiagnosticsLog
    ) -> SettingsScreen {
        let keys = KeychainSecretStore(diagnostics: diagnostics)
        return SettingsScreen(
            window: { model, themes in
                let recorder = HotkeyRecorderViewModel(
                    settings: settings, source: NSEventHotkeyCaptureSource(),
                    isTakenBySystem: { SystemShortcuts.isTaken($0) })
                return SettingsWindowController(
                    model: model, themes: themes, recorder: AnyView(HotkeyRecorderContainer(model: recorder)))
            },
            hasKey: { keys.hasSecret(for: $0) },
            hotkey: { Self.describe(settings.hotkeyConfiguration()) },
            secureInputActive: { IsSecureEventInputEnabled() },
            overlayVariants: [OverlayVariantOption(id: OverlayVariantOption.defaultID, title: "Default")],
            style: StyleSettingsRepository(store: settings),
            dictionary: DictionaryStore(settings: settings),
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

    /// The configured hotkey as key caps, from the setting the hotkey service reads.
    @MainActor
    private static func describe(_ configuration: HotkeyConfiguration) -> HotkeyDescription {
        HotkeyDescription(
            keys: HotkeyKeyCaps.caps(for: configuration), isModifierOnly: configuration.kind == .modifierOnly)
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

/// Whether a cloud recognizer has its key in the Keychain. The key itself is not read.
private struct KeychainProviderCredentials: ProviderCredentials {
    let keys: KeychainSecretStore

    func hasKey(for provider: ASRProviderID) -> Bool {
        SecretAccount(rawValue: provider.rawValue).map { keys.hasSecret(for: $0) } ?? false
    }
}
