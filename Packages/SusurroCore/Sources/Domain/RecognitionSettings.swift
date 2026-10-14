/// How far the user wants the language of a dictation to be guaranteed.
public enum SpeechLanguageMode: String, Sendable, Equatable, CaseIterable {
    /// The recognizer detects the language itself. It is the fastest, and on a short clip it can answer in the wrong
    /// language.
    case fast
    /// The language is pinned to Spanish. A transcript that comes back in another language is transcribed again by a
    /// recognizer that honors the pinned language, which costs time only on those clips.
    case guaranteedSpanish

    /// The language code the recognizer is asked for, or nil to let it detect the language.
    public var pinnedLanguage: String? {
        switch self {
        case .fast: nil
        case .guaranteedSpanish: "es"
        }
    }
}

public enum RecognitionSettings {
    /// The id of the selected recognizer. An id that no registered recognizer has reads as the default one.
    public static let provider = SettingKey<String>(
        area: "recognition", name: "provider", default: ASRProviderID.parakeetV3.rawValue)

    /// Whether the user turned a cloud recognizer on. Nothing is sent to a service until this is true, the recognizer is
    /// selected, and it has a key. Provider ids have no dots.
    public static func cloudEnabled(for provider: ASRProviderID) -> SettingKey<Bool> {
        SettingKey<Bool>(area: "recognition", name: "enabled-\(provider.rawValue)", default: false)
    }

    /// The language choice of the Settings screen.
    public static let languageMode = SettingKey<SpeechLanguageMode>(
        area: "recognition", name: "languageMode", default: .guaranteedSpanish)
}

/// What the pipeline reads of the user's language choice. A port this narrow keeps the settings screen and the pipeline
/// apart: the screen writes `RecognitionSettings.languageMode`, and the pipeline asks here.
public protocol LanguagePreference: Sendable {
    func mode() -> SpeechLanguageMode
}

/// The language choice as the settings store holds it.
public struct SettingsLanguagePreference: LanguagePreference {
    private let settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    public func mode() -> SpeechLanguageMode {
        settings.value(for: RecognitionSettings.languageMode)
    }
}
