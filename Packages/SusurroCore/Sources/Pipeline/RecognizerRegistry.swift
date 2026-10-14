import Domain

/// The recognizers the app has, and which of them is selected. The pipeline asks the registry for the recognizer of the
/// next dictation and knows nothing else about providers, so swapping one for another changes no pipeline code.
///
/// The selection is a setting, so it survives a relaunch. A fresh install, or a selection that names a recognizer the app
/// does not have, resolves to the default one. A cloud recognizer is usable only when the user turned it on and a key
/// is stored, and the audio of a dictation goes to a service only when the recognizer that is selected is usable.
public struct RecognizerRegistry: Sendable {
    private let providers: [any SpeechRecognizer]
    private let defaultProvider: ASRProviderID
    private let settings: any SettingsStore
    private let credentials: any ProviderCredentials

    /// - Parameters:
    ///   - providers: Every recognizer the app has. One of them is `defaultProvider`.
    ///   - defaultProvider: What a fresh install uses, and what a cloud failure falls back to. It runs on this Mac.
    public init(
        providers: [any SpeechRecognizer],
        defaultProvider: ASRProviderID = .parakeetV3,
        settings: any SettingsStore,
        credentials: any ProviderCredentials = NoProviderCredentials()
    ) {
        precondition(
            providers.contains { $0.id == defaultProvider }, "The default recognizer must be one of the providers")
        self.providers = providers
        self.defaultProvider = defaultProvider
        self.settings = settings
        self.credentials = credentials
    }

    /// The recognizer of the next dictation.
    public func selected() -> any SpeechRecognizer {
        let id = ASRProviderID(settings.value(for: RecognitionSettings.provider))
        return provider(id) ?? defaultRecognizer
    }

    /// The recognizer a cloud failure falls back to, or nil when the selected one is already the default.
    public func fallback(from failed: any SpeechRecognizer) -> (any SpeechRecognizer)? {
        failed.id == defaultProvider ? nil : defaultRecognizer
    }

    public func provider(_ id: ASRProviderID) -> (any SpeechRecognizer)? {
        providers.first { $0.id == id }
    }

    /// Why `recognizer` cannot be used, or nil when it can. A local recognizer always can.
    public func blocker(of recognizer: any SpeechRecognizer) -> ProviderBlocker? {
        guard recognizer.locality == .cloud else { return nil }
        guard settings.value(for: RecognitionSettings.cloudEnabled(for: recognizer.id)) else { return .notEnabled }
        return credentials.hasKey(for: recognizer.id) ? nil : .missingKey
    }

    private var defaultRecognizer: any SpeechRecognizer {
        provider(defaultProvider) ?? providers[0]
    }
}
