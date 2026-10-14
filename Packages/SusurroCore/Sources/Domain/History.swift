import Foundation

/// How an attempt stands. A record is created as `processing` when its audio is committed, before recognition.
public enum DictationStatus: String, Sendable, Equatable, CaseIterable {
    case processing
    case succeeded
    case noSpeech = "no-speech"
    case failed
    /// The user cancelled. The audio is kept and nothing was inserted.
    case cancelled
}

/// What happened to the final text once it left the pipeline.
public enum DictationDelivery: String, Sendable, Equatable, CaseIterable {
    case inserted
    case copiedToClipboard
    /// The text is only in the record: the history is the way to get it back.
    case notInserted

    public init(_ outcome: InsertionOutcome) {
        switch outcome {
        case .inserted: self = .inserted
        case .copiedToClipboard: self = .copiedToClipboard
        case .notInserted: self = .notInserted
        }
    }
}

/// One dictation attempt whose audio was stored.
///
/// A record never holds text from the field the user dictated into: no text around the cursor, no selection, and no
/// text read from the screen. Keep it that way when adding a field.
public struct DictationRecord: Sendable, Equatable, Identifiable {
    /// The `failure` of a record that was still `processing` when the app quit, which startup recovery marks failed.
    public static let interruptedFailure = "interrupted"

    /// The session id of the dictation: also the name of its audio file.
    public var id: UUID
    public var createdAt: Date
    public var duration: Duration
    public var status: DictationStatus
    public var rawText: String?
    /// The text after cleanup, or nil when cleanup did not run or fell back to the raw text.
    public var cleanedText: String?
    /// The text that was handed to the inserter.
    public var finalText: String?
    public var asrProvider: ASRProviderID?
    public var cleanerProvider: String?
    /// Why cleanup or a cloud provider fell back, when one did.
    public var fallbackReason: String?
    public var appName: String?
    public var bundleID: String?
    public var urlHost: String?
    /// The category of the style that applied, as its stable name.
    public var category: String?
    /// The tone of the style that applied, as its stable name.
    public var tone: String?
    public var styleSource: String?
    public var delivery: DictationDelivery?
    /// The stored audio, or nil once it expired or when there is none.
    public var audioURL: URL?
    /// True once the retention job deleted the audio. The record stays.
    public var audioExpired: Bool
    /// What went wrong when the status is `failed`: the name of a `PipelineError.kind`, or `interruptedFailure`. Never
    /// the text of an error, which can quote what the user said.
    public var failure: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        duration: Duration,
        status: DictationStatus = .processing,
        rawText: String? = nil,
        cleanedText: String? = nil,
        finalText: String? = nil,
        asrProvider: ASRProviderID? = nil,
        cleanerProvider: String? = nil,
        fallbackReason: String? = nil,
        appName: String? = nil,
        bundleID: String? = nil,
        urlHost: String? = nil,
        category: String? = nil,
        tone: String? = nil,
        styleSource: String? = nil,
        delivery: DictationDelivery? = nil,
        audioURL: URL? = nil,
        audioExpired: Bool = false,
        failure: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.status = status
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.finalText = finalText
        self.asrProvider = asrProvider
        self.cleanerProvider = cleanerProvider
        self.fallbackReason = fallbackReason
        self.appName = appName
        self.bundleID = bundleID
        self.urlHost = urlHost
        self.category = category
        self.tone = tone
        self.styleSource = styleSource
        self.delivery = delivery
        self.audioURL = audioURL
        self.audioExpired = audioExpired
        self.failure = failure
    }

    /// Whether the audio can still be used to retry the dictation.
    public var hasAudio: Bool { audioURL != nil && !audioExpired }
}

public enum HistoryError: Error, Sendable, Equatable {
    /// `update` or `markAudioExpired` named a record that is not in the history.
    case recordNotFound(UUID)
    /// `insert` named a record that is already in the history.
    case duplicateRecord(UUID)
}

/// Where the dictation records live. The live adapter is a GRDB database; tests use `InMemoryHistoryRepository`.
///
/// Every list is newest first. Nothing here ever deletes audio: the files belong to `AudioFileDeleting`, and the
/// callers that remove records or expire audio do the files themselves.
public protocol HistoryRepository: Sendable {
    /// Adds a record. Throws `HistoryError.duplicateRecord` when the id is taken.
    func insert(_ record: DictationRecord) async throws
    /// Replaces the record that has the same id. Throws `HistoryError.recordNotFound` when there is none.
    func update(_ record: DictationRecord) async throws
    func record(id: UUID) async throws -> DictationRecord?
    /// The records from `offset`, newest first, at most `limit`.
    func page(offset: Int, limit: Int) async throws -> [DictationRecord]
    /// The records still `processing` that have audio. At launch they are the attempts the last run did not finish.
    func recoverable() async throws -> [DictationRecord]
    /// Marks every record that is still `processing` as `failed` with `DictationRecord.interruptedFailure`, keeping its
    /// audio, and returns how many it changed. It is for launch, before any dictation can be under way.
    func failInterrupted() async throws -> Int
    /// The records whose audio is still stored and that were created before `cutoff`.
    func audioOlderThan(_ cutoff: Date) async throws -> [DictationRecord]
    /// Records that the audio is gone: sets `audioExpired` and clears `audioURL`. Throws
    /// `HistoryError.recordNotFound` when there is no such record.
    func markAudioExpired(_ id: UUID) async throws
    /// Removes the record. Removing one that is not there is not an error.
    func delete(_ id: UUID) async throws
    /// Removes every record except the ones in `keeping`.
    func deleteAll(keeping: Set<UUID>) async throws
    /// A new stream on each call: it yields once after each committed change to the history, and does not begin with a
    /// value. The consumer reads again what it shows.
    func changes() -> AsyncStream<Void>
}

extension HistoryRepository {
    public func deleteAll() async throws {
        try await deleteAll(keeping: [])
    }
}
