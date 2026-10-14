import Domain
import Foundation

public enum HistoryActionError: Error, Sendable, Equatable {
    case recordNotFound
    /// The record has no text of the kind that was asked for.
    case nothingToCopy
    /// This many audio files could not be deleted. Their records were kept, so that the audio is not left on the disk
    /// with nothing to point to it, and the deletion can be tried again.
    case audioNotDeleted(count: Int)
}

/// What the user does with a record of the history: copy its text, and delete it with its audio.
public struct HistoryActions: Sendable {
    private let repository: any HistoryRepository
    private let deleter: any AudioFileDeleting
    private let clipboard: any ClipboardWriting

    public init(repository: any HistoryRepository, deleter: any AudioFileDeleting, clipboard: any ClipboardWriting) {
        self.repository = repository
        self.deleter = deleter
        self.clipboard = clipboard
    }

    /// Puts the transcript as the recognizer wrote it on the clipboard.
    public func copyRaw(_ id: UUID) async throws {
        try await copy(id) { $0.rawText }
    }

    /// Puts the transcript after cleanup on the clipboard.
    public func copyCleaned(_ id: UUID) async throws {
        try await copy(id) { $0.cleanedText }
    }

    /// Deletes the audio file of a record and then the record. If the file cannot be deleted the record stays and
    /// `audioNotDeleted` is thrown. A record that is not there is not an error.
    public func delete(_ id: UUID) async throws {
        guard let record = try await repository.record(id: id) else { return }
        if let url = record.audioURL {
            do {
                try await deleter.delete(url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw HistoryActionError.audioNotDeleted(count: 1)
            }
        }
        try await repository.delete(id)
    }

    /// Deletes every record and its audio, except the dictations that are still being processed. A record whose file
    /// cannot be deleted stays, the rest go, and `audioNotDeleted` says how many stayed.
    public func deleteAll() async throws {
        var keeping = Set(try await repository.recoverable().map(\.id))
        var notDeleted = 0
        for record in try await repository.audioOlderThan(.distantFuture) where !keeping.contains(record.id) {
            guard let url = record.audioURL else { continue }
            do {
                try await deleter.delete(url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                keeping.insert(record.id)
                notDeleted += 1
            }
        }
        try await repository.deleteAll(keeping: keeping)
        if notDeleted > 0 { throw HistoryActionError.audioNotDeleted(count: notDeleted) }
    }

    private func copy(_ id: UUID, text: (DictationRecord) -> String?) async throws {
        guard let record = try await repository.record(id: id) else { throw HistoryActionError.recordNotFound }
        guard let text = text(record), !text.isEmpty else { throw HistoryActionError.nothingToCopy }
        await clipboard.copy(text)
    }
}
