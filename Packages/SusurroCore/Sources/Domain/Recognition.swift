public enum RecognizerReadiness: Sendable, Equatable {
    case notInstalled
    case loading(progress: Double)
    case ready
}

public struct RawTranscript: Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct RecognitionOptions: Sendable, Equatable {
    /// A language code such as "es", or nil for automatic detection.
    public var language: String?

    public init(language: String? = nil) {
        self.language = language
    }
}

public protocol SpeechRecognizer: Sendable {
    func readiness() async -> RecognizerReadiness
    func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript
}
