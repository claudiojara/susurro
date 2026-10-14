// The cleanup port: what a provider is given to clean a transcript, and what it says about itself. The cloud request is a
// type of its own with no context, selection, or screen text in it, so a cloud provider cannot be given any: the data
// boundary is in the type and checked again where a cloud provider takes its payload.
//
// The pipeline stage that builds these requests lives with the cleanup slice. The cloud providers read them.

/// Whether a cleaner can be used now.
public enum CleanerAvailability: Sendable, Equatable {
    case available
    /// Not usable. The text says why, ready to show: the cleaner is off, it has no key, the model is missing.
    case unavailable(String)
}

/// What a local cleaner is given: the transcript, the style, the vocabulary, and a bounded piece of the text before the
/// cursor, as reference for the spelling and the tone.
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

/// What a cloud cleaner is given: the transcript, the style, and the vocabulary, and nothing else. There is no field for
/// the text around the cursor, the selection, or the screen, so none can be sent.
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

/// A cloud cleaner was given a payload that is not a cloud one.
public struct CloudBoundaryViolation: Error, Sendable, Equatable {
    public init() {}
}

extension CleanupPayload {
    /// The cloud request, or a `CloudBoundaryViolation` for a local payload: a cloud cleaner never reads a local one.
    public func requireCloud() throws -> CloudCleanupRequest {
        guard case .cloud(let request) = self else { throw CloudBoundaryViolation() }
        return request
    }
}

/// A provider that cleans a transcript: punctuation, tone, and spelling, never the meaning.
public protocol TranscriptCleaner: Sendable {
    /// Whether the transcript stays on this Mac.
    var locality: Locality { get }
    func availability() async -> CleanerAvailability
    func clean(_ payload: CleanupPayload) async throws -> String
}
