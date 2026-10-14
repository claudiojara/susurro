import Domain
import Foundation

/// Deletes the audio of a dictation 7 days after its record was created, and keeps the text for good.
///
/// A deletion that fails is not marked: the record keeps its audio reference, so the next run tries again. The record
/// itself is never removed here, so the history still shows what was said, with the audio marked as expired.
public actor RetentionSweeper {
    /// How long audio is kept after the record is created.
    public static let audioRetention: TimeInterval = 7 * 24 * 60 * 60
    /// The pause between runs. Six hours meets the "at least daily" requirement even for a Mac that sleeps for much of the
    /// day, since the app also sweeps when it starts.
    public static let interval = Duration.seconds(6 * 60 * 60)

    /// What a sweep did: the audio it deleted, and the files that could not be deleted and will be tried again.
    public struct Report: Sendable, Equatable {
        public let expired: Int
        public let failed: Int

        public init(expired: Int, failed: Int) {
            self.expired = expired
            self.failed = failed
        }
    }

    private let repository: any HistoryRepository
    private let deleter: any AudioFileDeleting
    private let dates: any DateSource
    private let clock: any Clock<Duration>

    public init(
        repository: any HistoryRepository, deleter: any AudioFileDeleting, dates: any DateSource,
        clock: any Clock<Duration>
    ) {
        self.repository = repository
        self.deleter = deleter
        self.dates = dates
        self.clock = clock
    }

    /// Deletes the audio that is older than the retention and marks its records. A file that cannot be deleted is counted
    /// and left for the next sweep, and it does not stop the others. Throws when the history cannot be read.
    @discardableResult
    public func sweep() async throws -> Report {
        let cutoff = dates.now().addingTimeInterval(-Self.audioRetention)
        var expired = 0
        var failed = 0
        for record in try await repository.audioOlderThan(cutoff) {
            guard let url = record.audioURL else { continue }
            do {
                try await deleter.delete(url)
                try await repository.markAudioExpired(record.id)
                expired += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed += 1
            }
        }
        return Report(expired: expired, failed: failed)
    }

    /// Sweeps now and then every `interval`, until the task is cancelled. A sweep that fails is tried again at the next
    /// turn.
    public func run() async {
        while !Task.isCancelled {
            _ = try? await sweep()
            guard (try? await clock.sleep(for: Self.interval)) != nil else { return }
        }
    }
}
