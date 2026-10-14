import Domain
import Foundation

/// Why a retry was not started.
public enum RetryRefusal: Sendable, Equatable {
    case recordNotFound
    /// The 7 days of audio retention are over. The record shows it, and the text stays.
    case audioExpired
    /// The record never had audio to run again.
    case noAudio
    /// The record is a dictation that is still being processed.
    case stillProcessing
    /// A retry of this record is already running.
    case alreadyRetrying
}

public enum RetryResult: Sendable, Equatable {
    /// The retry ran. The status of the record says how it ended: `succeeded`, `noSpeech`, or `failed`.
    case completed(DictationRecord)
    case refused(RetryRefusal)
}

/// Runs a stored recording through the pipeline stages again and updates its record. Nothing is inserted: the new text is
/// in the record, and the user copies it from the history.
///
/// A retry does not go through the `ProcessingQueue`. It never inserts, so it neither waits for live dictations nor holds
/// them back.
public actor RetryService {
    /// The `failure` of a record whose audio could not be read back.
    public static let audioUnreadableFailure = "audioUnreadable"

    private let repository: any HistoryRepository
    private let loader: any AudioClipLoading
    private let reprocessor: any DictationReprocessing
    private var retrying: Set<UUID> = []

    public init(
        repository: any HistoryRepository, loader: any AudioClipLoading, reprocessor: any DictationReprocessing
    ) {
        self.repository = repository
        self.loader = loader
        self.reprocessor = reprocessor
    }

    /// Retries the dictation of a record. A retry that runs and fails is not an error here: the record ends `failed`, with
    /// the name of the failure, and can be retried again. It throws when the history cannot be read or written, and
    /// `CancellationError` when the task is cancelled, in which case the record is put back as it was.
    public func retry(_ id: UUID) async throws -> RetryResult {
        guard retrying.insert(id).inserted else { return .refused(.alreadyRetrying) }
        defer { retrying.remove(id) }

        guard let original = try await repository.record(id: id) else { return .refused(.recordNotFound) }
        if original.status == .processing { return .refused(.stillProcessing) }
        if original.audioExpired { return .refused(.audioExpired) }
        guard let url = original.audioURL else { return .refused(.noAudio) }

        var working = original
        working.status = .processing
        try await repository.update(working)

        let finished: DictationRecord
        do {
            let clip = try await loadClip(at: url)
            finished = Self.apply(try await reprocessor.reprocess(clip, for: original), to: original)
        } catch is CancellationError {
            try? await repository.update(original)
            throw CancellationError()
        } catch is UnreadableAudio {
            finished = Self.failed(original, Self.audioUnreadableFailure)
        } catch let error as PipelineError {
            finished = Self.failed(original, error.kind)
        } catch {
            finished = Self.failed(original, "retryFailed")
        }
        try await repository.update(finished)
        return .completed(finished)
    }

    // MARK: Outcomes

    private struct UnreadableAudio: Error {}

    private func loadClip(at url: URL) async throws -> AudioClip {
        do {
            return try await loader.clip(at: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UnreadableAudio()
        }
    }

    /// The record after a retry that produced `outcome`. The audio, the style, and the app stay as they were.
    private static func apply(_ outcome: ReprocessOutcome, to original: DictationRecord) -> DictationRecord {
        var record = original
        record.failure = nil
        // The new text was not delivered anywhere, so what the record says about the old text no longer applies.
        record.delivery = nil
        switch outcome {
        case .text(let text):
            record.status = .succeeded
            record.rawText = text.rawText
            record.cleanedText = text.cleanedText
            record.finalText = text.finalText
            record.asrProvider = text.asrProvider
            record.cleanerProvider = text.cleanerProvider
            record.fallbackReason = text.fallbackReason
        case .noSpeech:
            record.status = .noSpeech
        }
        return record
    }

    /// The record after a retry that failed: failed, with the old text kept so that nothing the user could copy is lost.
    private static func failed(_ original: DictationRecord, _ failure: String) -> DictationRecord {
        var record = original
        record.status = .failed
        record.failure = failure
        return record
    }
}
