/// The ids the settings store for the providers, which the recognizers and the cleaners answer to.
public enum ProviderID {
    public static let parakeetV3 = "parakeet-v3"
    public static let localWhisper = "local-whisper"
    public static let deepgram = "deepgram"
    public static let appleIntelligence = "apple-intelligence"
    public static let anthropic = "anthropic"
    public static let openAICompatible = "openai-compatible"
}

/// The settings of speech recognition. A value nobody set is the default, and a stored value that does not read as its
/// type is the default too.
public enum SpeechSettings {
    /// The language choice. It is the pipeline's key: the General picker writes it and the recognition runner reads it.
    public static var languageMode: SettingKey<SpeechLanguageMode> { RecognitionSettings.languageMode }

    /// The `ASRProviderID` of the recognizer in use, as the recognizer registry reads it.
    public static var provider: SettingKey<String> { RecognitionSettings.provider }

    /// Whether the user turned Deepgram on. A cloud provider is unusable until it is on and has a key.
    public static var deepgramEnabled: SettingKey<Bool> {
        RecognitionSettings.cloudEnabled(for: ASRProviderID(ProviderID.deepgram))
    }

    public static let localWhisperMode = SettingKey<LocalWhisperMode>(
        area: "localWhisper", name: "mode", default: .http)
    public static let localWhisperServerStyle = SettingKey<LocalWhisperServerStyle>(
        area: "localWhisper", name: "serverStyle", default: .openAICompatible)
    /// The endpoint of the user's Whisper server. It must be on this Mac (`LoopbackEndpoint`).
    public static let localWhisperEndpoint = SettingKey<String>(
        area: "localWhisper", name: "endpoint", default: "http://127.0.0.1:8080/v1/audio/transcriptions")
    /// The absolute path of the user's Whisper command line tool, for the `cli` mode.
    public static let localWhisperExecutable = SettingKey<String>(area: "localWhisper", name: "executable", default: "")
    /// The model name sent to the server, or empty to send none.
    public static let localWhisperModel = SettingKey<String>(area: "localWhisper", name: "model", default: "")

    /// Every key, for the check that none share a storage name.
    public static var all: [any AnySettingKey] {
        [
            languageMode, provider, deepgramEnabled, localWhisperMode, localWhisperServerStyle, localWhisperEndpoint,
            localWhisperExecutable, localWhisperModel,
        ]
    }
}

/// How the local Whisper provider reaches the user's install.
public enum LocalWhisperMode: String, Sendable, Equatable, CaseIterable {
    /// Multipart WAV to a server on this Mac.
    case http
    /// The user's command line tool, run as a process.
    case cli
}

/// What the local Whisper server speaks.
public enum LocalWhisperServerStyle: String, Sendable, Equatable, CaseIterable {
    /// `/v1/audio/transcriptions` with `model`, `language`, `prompt`, and `response_format` fields.
    case openAICompatible
    /// The `whisper.cpp` server's `/inference` endpoint.
    case whisperCpp
}

/// The settings of the cloud cleaners. `CleanupSettings.enabled` and `CleanupSettings.provider` are the cleanup stage's.
extension CleanupSettings {
    public static let anthropicEnabled = SettingKey<Bool>(area: "anthropic", name: "enabled", default: false)
    public static let anthropicModel = SettingKey<String>(
        area: "anthropic", name: "model", default: "claude-haiku-4-5")

    public static let openAICompatibleEnabled = SettingKey<Bool>(
        area: "openaiCompatible", name: "enabled", default: false)
    /// The base URL of the service, such as `https://api.openai.com/v1`.
    public static let openAICompatibleBaseURL = SettingKey<String>(
        area: "openaiCompatible", name: "baseURL", default: "https://api.openai.com/v1")
    public static let openAICompatibleModel = SettingKey<String>(
        area: "openaiCompatible", name: "model", default: "gpt-4o-mini")

    public static var all: [any AnySettingKey] {
        [
            enabled, provider, anthropicEnabled, anthropicModel, openAICompatibleEnabled, openAICompatibleBaseURL,
            openAICompatibleModel,
        ]
    }
}

/// The settings of the General screen that other parts of the app read.
public enum GeneralSettings {
    /// Whether the text around the cursor and the name of the app are read as context. On by default.
    public static var appContextEnabled: SettingKey<Bool> { ContextSettings.useAppContext }
    /// Whether the text on the screen is read with OCR. Off by default.
    public static var ocrEnabled: SettingKey<Bool> { ContextSettings.ocrEnabled }
    public static let overlayEdge = SettingKey<OverlayEdge>(area: "overlay", name: "edge", default: .bottom)
    /// The id of the overlay variant. An id nobody registered falls back to the default variant.
    public static let overlayVariant = SettingKey<String>(area: "overlay", name: "variant", default: "default")
    /// The language of the app's own words. It is not the language of the dictation, which `languageMode` sets.
    public static let interfaceLanguage = SettingKey<InterfaceLanguage>(
        area: "interface", name: "language", default: .system)

    public static var all: [any AnySettingKey] {
        [appContextEnabled, ocrEnabled, overlayEdge, overlayVariant, interfaceLanguage]
    }
}

/// The language the app shows its own words in: the system's, or one the user picked. Only the menu, the windows and the
/// overlay follow it; what is dictated keeps the language of `SpeechLanguageMode`.
public enum InterfaceLanguage: String, Sendable, Equatable, CaseIterable {
    case system
    case english = "en"
    case spanish = "es"

    /// The languages the app has words for, by their code. English is the source and the fallback.
    public static let available = ["en", "es"]

    /// The code of the language to show: the chosen one, or for `system` the first of the user's preferred languages
    /// (as `Locale.preferredLanguages` lists them, such as `es-CL`) that the app has, and English when none is.
    public func resolved(preferredLanguages: [String]) -> String {
        switch self {
        case .english, .spanish: return rawValue
        case .system:
            for identifier in preferredLanguages {
                let code = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(
                    String.init)
                if let code, Self.available.contains(code) { return code }
            }
            return "en"
        }
    }
}

/// The edge of the screen the overlay sits on.
public enum OverlayEdge: String, Sendable, Equatable, CaseIterable {
    case top, bottom
}
