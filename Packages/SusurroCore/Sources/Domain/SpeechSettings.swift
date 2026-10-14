/// The language the speech recognizer is asked for. Automatic detection is the fast choice, and pinning a language is
/// the guaranteed one: the speech models detect the language themselves and can misfire on short clips, so a user who
/// always dictates in one language can ask for it.
public enum SpeechLanguage: String, Sendable, Equatable, CaseIterable {
    /// The recognizer detects the language of each clip.
    case auto
    /// The recognizer is asked for Spanish ("es").
    case spanish = "es"

    /// The code passed to the recognizer in `RecognitionOptions.language`, or nil for automatic detection.
    public var code: String? {
        switch self {
        case .auto: nil
        case .spanish: rawValue
        }
    }
}

/// Where the recognizer side reads the language the user chose, so that it never reads the settings store itself. The
/// value is read for each dictation, so a change applies to the next one.
public protocol RecognitionLanguageSource: Sendable {
    /// The language code to pin, such as "es", or nil for automatic detection.
    func language() -> String?
}

/// The language the user chose in the settings.
public struct SettingsRecognitionLanguage: RecognitionLanguageSource {
    private let settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    public func language() -> String? {
        settings.value(for: SpeechSettings.language).code
    }
}

/// The settings of speech recognition. A value nobody set is the default, and a stored value that does not read as its
/// type is the default too.
public enum SpeechSettings {
    public static let language = SettingKey<SpeechLanguage>(area: "speech", name: "language", default: .auto)

    /// The `ASRProviderID` of the recognizer in use. Parakeet v3 until the user picks another one.
    public static let provider = SettingKey<String>(area: "asr", name: "provider", default: "parakeet-v3")

    /// Whether the user turned Deepgram on. A cloud provider is unusable until it is on and has a key.
    public static let deepgramEnabled = SettingKey<Bool>(area: "deepgram", name: "enabled", default: false)

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
            language, provider, deepgramEnabled, localWhisperMode, localWhisperServerStyle, localWhisperEndpoint,
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

/// The settings of the transcript cleanup.
public enum CleanupSettings {
    /// Whether the transcript is cleaned at all. On until the user turns it off.
    public static let enabled = SettingKey<Bool>(area: "cleanup", name: "enabled", default: true)
    /// The id of the cleaner in use. Apple's on-device model until the user picks another one.
    public static let provider = SettingKey<String>(area: "cleanup", name: "provider", default: "apple-intelligence")

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
    public static let appContextEnabled = SettingKey<Bool>(area: "context", name: "useAppContext", default: true)
    /// Whether the text on the screen is read with OCR. Off by default.
    public static let ocrEnabled = SettingKey<Bool>(area: "context", name: "ocrEnabled", default: false)
    public static let overlayEdge = SettingKey<OverlayEdge>(area: "overlay", name: "edge", default: .bottom)
    /// The id of the overlay variant. An id nobody registered falls back to the default variant.
    public static let overlayVariant = SettingKey<String>(area: "overlay", name: "variant", default: "default")

    public static var all: [any AnySettingKey] {
        [appContextEnabled, ocrEnabled, overlayEdge, overlayVariant]
    }
}

/// The edge of the screen the overlay sits on.
public enum OverlayEdge: String, Sendable, Equatable, CaseIterable {
    case top, bottom
}
