/// The stable name under which a cleaner is selected and recorded.
public struct CleanerProviderID: Sendable, Hashable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appleIntelligence = CleanerProviderID("apple-intelligence")
}

/// Whether a cleaner can take a request now.
public enum CleanerAvailability: Sendable, Equatable {
    case available
    /// The text is the reason, shown to the user. It never quotes a dictation.
    case unavailable(String)
}

/// What a cleaner may receive when it runs on this Mac: the transcript, the style, the vocabulary, and the bounded text
/// before the cursor.
public struct LocalCleanupRequest: Sendable, Equatable {
    public let transcript: String
    public let style: StyleProfile
    public let vocabulary: [String]
    public let beforeCursor: String

    public init(transcript: String, style: StyleProfile, vocabulary: [String], beforeCursor: String) {
        self.transcript = transcript
        self.style = style
        self.vocabulary = vocabulary
        self.beforeCursor = beforeCursor
    }
}

/// What a cleaner may receive when it runs in the cloud: the transcript, the style, and the vocabulary, and nothing
/// else. The type has no field for text around the cursor, a selection, or text read from the screen, so none can leak
/// through it. `CloudBoundaryTests` pins its stored properties.
public struct CloudCleanupRequest: Sendable, Equatable {
    public let transcript: String
    public let style: StyleProfile
    public let vocabulary: [String]

    public init(transcript: String, style: StyleProfile, vocabulary: [String]) {
        self.transcript = transcript
        self.style = style
        self.vocabulary = vocabulary
    }
}

public enum CleanupPayload: Sendable, Equatable {
    case local(LocalCleanupRequest)
    case cloud(CloudCleanupRequest)
}

/// A cloud adapter received a payload with local context in it. The type and the factory make it impossible, and the
/// adapters check it anyway.
public struct CloudBoundaryViolation: Error, Sendable, Equatable {
    public init() {}
}

extension CleanupPayload {
    /// The request of a cloud payload. A local payload throws `CloudBoundaryViolation`, so a cloud adapter that was
    /// handed context refuses it instead of sending it.
    public func requireCloud() throws -> CloudCleanupRequest {
        guard case .cloud(let request) = self else { throw CloudBoundaryViolation() }
        return request
    }

    /// The request of a local payload. A cloud payload throws `CloudBoundaryViolation`.
    public func requireLocal() throws -> LocalCleanupRequest {
        guard case .local(let request) = self else { throw CloudBoundaryViolation() }
        return request
    }
}

/// Why a cleaner could not return text. The stage maps each to a `FallbackReason`; the raw transcript is used.
public enum CleanerError: Error, Sendable, Equatable {
    /// The cleaner's safety system refused the text.
    case guardrail
    /// The request does not fit the model's context window.
    case contextWindowExceeded
    /// The cleaner is not available. The text is the reason.
    case unavailable(String)
    /// The cleaner failed. The text is the underlying error, which can quote the dictation: it is never logged.
    case failed(String)
}

/// What a cleaner takes: the limits of its input and how long it may take. A transcript over the cap is not sent, and
/// the text before the cursor is trimmed first so that the request fits `maxInputCharacters`.
public struct ProviderBudget: Sendable, Equatable {
    /// The most characters of transcript the cleaner is given.
    public let maxTranscriptCharacters: Int
    /// The most characters of transcript and text before the cursor together. A cleaner that takes no context ignores it.
    public let maxInputCharacters: Int
    /// What every call gets, whatever the length of the transcript: the time to start the model.
    public let baseTimeout: Duration
    /// What a call gets on top of `baseTimeout` for each character of transcript: the time to write a faithful reply.
    public let timeoutPerCharacter: Duration
    /// The most a call may take, however long the transcript is.
    public let maxTimeout: Duration

    public init(
        maxTranscriptCharacters: Int, maxInputCharacters: Int, baseTimeout: Duration, timeoutPerCharacter: Duration,
        maxTimeout: Duration
    ) {
        self.maxTranscriptCharacters = maxTranscriptCharacters
        self.maxInputCharacters = maxInputCharacters
        self.baseTimeout = baseTimeout
        self.timeoutPerCharacter = timeoutPerCharacter
        self.maxTimeout = maxTimeout
    }

    /// A budget with one limit for every length of transcript.
    public init(maxTranscriptCharacters: Int, maxInputCharacters: Int, timeout: Duration) {
        self.init(
            maxTranscriptCharacters: maxTranscriptCharacters, maxInputCharacters: maxInputCharacters,
            baseTimeout: timeout, timeoutPerCharacter: .zero, maxTimeout: timeout)
    }

    /// How long a call may take for a transcript of this many characters before the raw transcript is used.
    public func timeout(forTranscriptCharacters count: Int) -> Duration {
        min(baseTimeout + timeoutPerCharacter * max(count, 0), maxTimeout)
    }

    /// Apple's on-device model: a context window of about 4,000 tokens shared by the instructions, the context, and the
    /// output, which is about as long as the input. The transcript cap is 2,500 characters, and the text before the
    /// cursor shrinks so that the two together stay within 2,800. The numbers were measured with the model's own token
    /// count on Spanish text (ADR 0008): the cap is conservative, not tight.
    ///
    /// The time follows the paste promise (ADR 0015): 1.2 s, and 8 ms for each character of transcript, which is the time
    /// the model takes to write a faithful reply (0.23 tokens a character at about 30 tokens a second), up to 6 s. A
    /// short question gets under 1.5 s, the sentence of the real-model checks 1.8 s, and a long text waits in proportion
    /// to what was said.
    public static let foundationModels = ProviderBudget(
        maxTranscriptCharacters: 2_500, maxInputCharacters: 2_800, baseTimeout: .milliseconds(1_200),
        timeoutPerCharacter: .milliseconds(8), maxTimeout: .seconds(6))

    /// A cloud cleaner takes no context, so only the transcript counts. A network call has no length to follow, so its
    /// limit is flat.
    public static let cloud = ProviderBudget(
        maxTranscriptCharacters: 6_000, maxInputCharacters: 6_000, timeout: .seconds(6))
}

/// The text around the cursor as far as it could be read. A dictation whose surroundings could not be read has no
/// `CursorContext` at all, which is different from an empty field: the shaper leaves the text alone for the first and
/// writes it as the start of a field for the second.
public struct CursorContext: Sendable, Equatable {
    public let before: String
    public let after: String

    public init(before: String, after: String) {
        self.before = before
        self.after = after
    }
}

/// Everything the cleanup stage needs to know about one dictation. The selection and the text read from the screen are
/// not here: they never reach the cleaner, locally or in the cloud.
public struct CleanupInput: Sendable, Equatable {
    public let transcript: String
    public let style: StyleProfile
    public let vocabulary: [String]
    public let cursor: CursorContext?

    public init(transcript: String, style: StyleProfile, vocabulary: [String] = [], cursor: CursorContext? = nil) {
        self.transcript = transcript
        self.style = style
        self.vocabulary = vocabulary
        self.cursor = cursor
    }
}

/// What cleanup produced for one dictation. `raw` and `cleaned` and the reason are what the history keeps.
public struct CleanupResult: Sendable, Equatable {
    /// The transcript as the recognizer produced it.
    public let raw: String
    /// The cleaner's text once it passed the checks, or nil when the raw transcript was used.
    public let cleaned: String?
    /// Why the raw transcript was used although cleanup was on, or nil when cleanup produced the text or was skipped.
    public let fallbackReason: FallbackReason?
    /// The cleaner that ran, or nil when none did.
    public let provider: CleanerProviderID?
    /// What goes into the app: the cleaned text or the raw one, shaped for the cursor.
    public let finalText: String

    public init(
        raw: String, cleaned: String?, fallbackReason: FallbackReason?, provider: CleanerProviderID?, finalText: String
    ) {
        self.raw = raw
        self.cleaned = cleaned
        self.fallbackReason = fallbackReason
        self.provider = provider
        self.finalText = finalText
    }
}

/// Turns a transcript into text that reads well in the target app. One protocol for every provider: the locality tells
/// the factory which payload to build.
public protocol TranscriptCleaner: Sendable {
    var id: CleanerProviderID { get }
    var locality: Locality { get }
    var budget: ProviderBudget { get }
    func availability() async -> CleanerAvailability
    /// A cloud cleaner takes only `.cloud` payloads and throws `CloudBoundaryViolation` on `.local`. A cancelled call
    /// throws `CancellationError`.
    func clean(_ payload: CleanupPayload) async throws -> String
    /// Gets the model ready for a request that is about to come, if it takes time to start. It never throws and its
    /// result is only an optimization: a cleaner that has nothing to prepare does nothing.
    func prewarm() async
}

extension TranscriptCleaner {
    public func prewarm() async {}
}
