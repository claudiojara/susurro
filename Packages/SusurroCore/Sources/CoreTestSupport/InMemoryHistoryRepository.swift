import Domain
import Foundation
import Synchronization

/// A history that keeps its records in memory and behaves as the database does: newest first with the id breaking a tie,
/// `HistoryError` for a record that is missing or taken, and a change stream that yields after each change.
public final class InMemoryHistoryRepository: HistoryRepository {
    private struct State {
        var records: [UUID: DictationRecord] = [:]
        var failure: (any Error)?
        var nextSubscriber = 0
        var subscribers: [Int: AsyncStream<Void>.Continuation] = [:]
    }

    private let state = Mutex(State())

    public init(records: [DictationRecord] = []) {
        state.withLock { state in
            for record in records { state.records[record.id] = record }
        }
    }

    /// Every record, newest first.
    public var allRecords: [DictationRecord] { state.withLock { Self.sorted($0.records.values) } }

    /// Makes every call after this one throw `error`, or work again when it is nil.
    public func failAllCalls(with error: (any Error)?) {
        state.withLock { $0.failure = error }
    }

    public func insert(_ record: DictationRecord) async throws {
        try change { state in
            guard state.records[record.id] == nil else { throw HistoryError.duplicateRecord(record.id) }
            state.records[record.id] = record
            return true
        }
    }

    public func update(_ record: DictationRecord) async throws {
        try change { state in
            guard state.records[record.id] != nil else { throw HistoryError.recordNotFound(record.id) }
            state.records[record.id] = record
            return true
        }
    }

    public func record(id: UUID) async throws -> DictationRecord? {
        try read { $0.records[id] }
    }

    public func page(offset: Int, limit: Int) async throws -> [DictationRecord] {
        try read { state in
            let sorted = Self.sorted(state.records.values)
            guard offset < sorted.count, limit > 0 else { return [] }
            return Array(sorted[max(offset, 0)..<min(sorted.count, max(offset, 0) + limit)])
        }
    }

    public func recoverable() async throws -> [DictationRecord] {
        try read { state in Self.sorted(state.records.values.filter { $0.status == .processing && $0.hasAudio }) }
    }

    public func failInterrupted(createdBefore launch: Date) async throws -> Int {
        var count = 0
        try change { state in
            for (id, record) in state.records where record.status == .processing && record.createdAt < launch {
                var failed = record
                failed.status = .failed
                failed.failure = DictationRecord.interruptedFailure
                state.records[id] = failed
                count += 1
            }
            return count > 0
        }
        return count
    }

    public func audioOlderThan(_ cutoff: Date) async throws -> [DictationRecord] {
        try read { state in Self.sorted(state.records.values.filter { $0.hasAudio && $0.createdAt < cutoff }) }
    }

    public func markAudioExpired(_ id: UUID) async throws {
        try change { state in
            guard var record = state.records[id] else { throw HistoryError.recordNotFound(id) }
            record.audioExpired = true
            record.audioURL = nil
            state.records[id] = record
            return true
        }
    }

    public func delete(_ id: UUID) async throws {
        try change { state in
            state.records.removeValue(forKey: id) != nil
        }
    }

    public func deleteAll(keeping: Set<UUID>) async throws {
        try change { state in
            let before = state.records.count
            state.records = state.records.filter { keeping.contains($0.key) }
            return state.records.count != before
        }
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = state.withLock { state in
                defer { state.nextSubscriber += 1 }
                state.subscribers[state.nextSubscriber] = continuation
                return state.nextSubscriber
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
            }
        }
    }

    // MARK: Helpers

    private func read<T>(_ body: (State) -> T) throws -> T {
        try state.withLock { state in
            if let failure = state.failure { throw failure }
            return body(state)
        }
    }

    /// Applies a change and tells the subscribers when it changed anything: `body` returns whether it did.
    private func change(_ body: (inout State) throws -> Bool) throws {
        let subscribers = try state.withLock { state -> [AsyncStream<Void>.Continuation] in
            if let failure = state.failure { throw failure }
            guard try body(&state) else { return [] }
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers { subscriber.yield() }
    }

    private static func sorted(_ records: some Sequence<DictationRecord>) -> [DictationRecord] {
        records.sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }
}
