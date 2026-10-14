public enum RecognizerReadiness: Sendable, Equatable {
    /// The model is missing and nothing is fetching it. The way out is in settings.
    case notInstalled
    /// The model is loading, or about to: `progress` is 0 until a load reports more. A model on disk that has not been
    /// loaded yet reads as loading, not as missing.
    case loading(progress: Double)
    case ready
    /// A load failed. The text says why. `retryable` is false when trying again cannot help: the failure is permanent,
    /// or the recognizer gave up. Dictating again is then not the way out.
    case unavailable(String, retryable: Bool)
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
    /// Terms the recognizer should favor. A recognizer that cannot bias its output ignores them.
    public var vocabulary: [String]

    public init(language: String? = nil, vocabulary: [String] = []) {
        self.language = language
        self.vocabulary = vocabulary
    }
}

/// Why a recognizer produced no transcript. A cancelled call throws `CancellationError`, never one of these.
public enum RecognitionError: Error, Sendable, Equatable {
    /// `transcribe` was called before `readiness()` reported `.ready`.
    case notReady
    /// The engine failed. The text is the underlying error.
    case engineFailed(String)
}

/// Whether a recognizer keeps audio on this Mac or sends it to a service.
public enum Locality: Sendable, Equatable {
    case local
    case cloud
}

/// The stable name under which a recognizer is selected and recorded.
public struct ASRProviderID: Sendable, Hashable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension ASRProviderID {
    /// The default provider: Parakeet v3, which runs on this Mac.
    public static let parakeetV3 = ASRProviderID("parakeet-v3")
}

public protocol SpeechRecognizer: Sendable {
    /// The name under which the recognizer is selected, and recorded in the history.
    var id: ASRProviderID { get }
    var locality: Locality { get }
    /// The longest clip the recognizer takes in one call, or nil when it takes any length. The pipeline splits a longer
    /// clip at silences and joins the transcripts in order.
    var maxClipDuration: Duration? { get }
    func readiness() async -> RecognizerReadiness
    /// Starts loading the model, or tries again after a failure, and returns at once. It does nothing while a load runs
    /// or once the model is ready, so calling it again is harmless. The coordinator calls it on every press that does
    /// not find the recognizer ready. A recognizer that needs no loading implements it as a function that does nothing;
    /// there is no default, so a conformer cannot forget it.
    func prepare() async
    func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript
}
