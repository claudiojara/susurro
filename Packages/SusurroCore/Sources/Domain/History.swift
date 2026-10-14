import Foundation

public enum DictationStatus: String, Sendable, Equatable, CaseIterable {
    case processing
    case succeeded
    case noSpeech
    case failed
    case cancelled
}

/// One dictation attempt whose audio was stored. It is created when the audio is committed, before recognition, and
/// updated as the attempt moves on. It never holds text from the screen.
public struct DictationRecord: Sendable, Equatable {
    public let id: SessionID
    public let createdAt: Date
    public var duration: Duration
    public var status: DictationStatus
    public var rawText: String?
    /// The text that went to the target app, or to the clipboard when the paste did not land.
    public var finalText: String?
    /// The recognizer that produced the raw text, which is not the selected one when a fallback ran.
    public var asrProvider: ASRProviderID?
    /// Why the first choice was left for another: a language guard or a failing provider.
    public var fallbackReason: String?
    /// The stored audio, until it expires.
    public var audioURL: URL?
    public var audioExpired: Bool
    /// `PipelineError.kind` of the failure that ended the attempt. Never the text of an error.
    public var errorKind: String?

    public init(
        id: SessionID,
        createdAt: Date,
        duration: Duration,
        status: DictationStatus = .processing,
        rawText: String? = nil,
        finalText: String? = nil,
        asrProvider: ASRProviderID? = nil,
        fallbackReason: String? = nil,
        audioURL: URL? = nil,
        audioExpired: Bool = false,
        errorKind: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.status = status
        self.rawText = rawText
        self.finalText = finalText
        self.asrProvider = asrProvider
        self.fallbackReason = fallbackReason
        self.audioURL = audioURL
        self.audioExpired = audioExpired
        self.errorKind = errorKind
    }
}

/// Where dictation attempts are kept. The pipeline needs only these calls; reading and retention come with the
/// history features.
public protocol HistoryRepository: Sendable {
    /// Adds the record of a new attempt.
    func insert(_ record: DictationRecord) async throws
    /// Replaces the stored record that has the same id.
    func update(_ record: DictationRecord) async throws
    func record(id: SessionID) async throws -> DictationRecord?
}
