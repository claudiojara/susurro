public struct ASRProviderID: Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public enum Locality: Sendable, Equatable {
    case local
    case cloud
}

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
    public var vocabulary: [String]

    public init(language: String? = nil, vocabulary: [String] = []) {
        self.language = language
        self.vocabulary = vocabulary
    }
}

public protocol SpeechRecognizer: Sendable {
    var id: ASRProviderID { get }
    var locality: Locality { get }
    var maxClipDuration: Duration? { get }
    func readiness() async -> RecognizerReadiness
    func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript
}
