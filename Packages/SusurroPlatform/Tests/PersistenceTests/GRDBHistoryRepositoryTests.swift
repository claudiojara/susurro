import CoreTestSupport
import Domain
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The history behaviors that both repositories must share: the database and the fake the pipeline tests run on.
@Suite("History repository contract", .timeLimit(.minutes(1)))
struct HistoryRepositoryContractTests {
    enum Kind: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case grdb
        case inMemory

        var testDescription: String { rawValue }

        func make() throws -> any HistoryRepository {
            switch self {
            case .grdb: try GRDBHistoryRepository(DatabaseQueue())
            case .inMemory: InMemoryHistoryRepository()
            }
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func record(
        _ id: UUID = UUID(), age: TimeInterval = 0, status: DictationStatus = .processing, audio: Bool = true
    ) -> DictationRecord {
        DictationRecord(
            id: id, createdAt: now.addingTimeInterval(-age), duration: .milliseconds(2500), status: status,
            audioURL: audio ? URL(filePath: "/audio/\(id.uuidString).caf") : nil)
    }

    @Test(
        "a record is inserted when the audio is committed and updated when recognition ends", arguments: Kind.allCases)
    func insertThenUpdate(kind: Kind) async throws {
        let repository = try kind.make()
        var record = Self.record()
        try await repository.insert(record)
        #expect(try await repository.record(id: record.id) == record)

        record.status = .succeeded
        record.rawText = "hola mundo"
        record.asrProvider = ASRProviderID("parakeet-v3")
        try await repository.update(record)

        let stored = try await repository.record(id: record.id)
        #expect(stored == record)
        #expect(stored?.status == .succeeded)
        #expect(stored?.rawText == "hola mundo")
    }

    @Test("every field of a record reads back as it was written", arguments: Kind.allCases)
    func everyFieldRoundTrips(kind: Kind) async throws {
        let repository = try kind.make()
        let record = DictationRecord(
            createdAt: Self.now, duration: .milliseconds(61_234), status: .failed, rawText: "raw",
            cleanedText: "Cleaned",
            finalText: "Final", asrProvider: ASRProviderID("parakeet-v3"), cleanerProvider: "foundation-models",
            fallbackReason: "cleanup timed out", appName: "Notes", bundleID: "com.apple.Notes", urlHost: "example.com",
            category: "notes", tone: "casual", styleSource: "seed", delivery: .copiedToClipboard,
            audioURL: URL(filePath: "/audio/x.caf"), audioExpired: false, failure: "recognitionFailed")
        try await repository.insert(record)

        #expect(try await repository.record(id: record.id) == record)
    }

    @Test("a record that is not there reads as nil, and updating or expiring it is an error", arguments: Kind.allCases)
    func missingRecords(kind: Kind) async throws {
        let repository = try kind.make()
        let missing = Self.record()

        #expect(try await repository.record(id: missing.id) == nil)
        await #expect(throws: HistoryError.recordNotFound(missing.id)) { try await repository.update(missing) }
        await #expect(throws: HistoryError.recordNotFound(missing.id)) {
            try await repository.markAudioExpired(missing.id)
        }
        try await repository.delete(missing.id)
    }

    @Test("inserting an id twice is an error and keeps the first record", arguments: Kind.allCases)
    func duplicateInsert(kind: Kind) async throws {
        let repository = try kind.make()
        let first = Self.record()
        try await repository.insert(first)
        var second = first
        second.rawText = "other"

        await #expect(throws: HistoryError.duplicateRecord(first.id)) { try await repository.insert(second) }
        #expect(try await repository.record(id: first.id) == first)
    }

    @Test("pages come newest first and the offset and limit cut them", arguments: Kind.allCases)
    func paging(kind: Kind) async throws {
        let repository = try kind.make()
        let ids = (0..<5).map { _ in UUID() }
        for (index, id) in ids.enumerated() { try await repository.insert(Self.record(id, age: Double(index) * 60)) }

        #expect(try await repository.page(offset: 0, limit: 2).map(\.id) == [ids[0], ids[1]])
        #expect(try await repository.page(offset: 2, limit: 2).map(\.id) == [ids[2], ids[3]])
        #expect(try await repository.page(offset: 4, limit: 2).map(\.id) == [ids[4]])
        #expect(try await repository.page(offset: 5, limit: 2).isEmpty)
        #expect(try await repository.page(offset: 0, limit: 0).isEmpty)
    }

    @Test("only a processing record with audio is recoverable", arguments: Kind.allCases)
    func recoverable(kind: Kind) async throws {
        let repository = try kind.make()
        let stale = Self.record(age: 10)
        try await repository.insert(stale)
        try await repository.insert(Self.record(status: .succeeded))
        try await repository.insert(Self.record(status: .failed))
        var expired = Self.record(age: 20)
        expired.audioURL = nil
        expired.audioExpired = true
        try await repository.insert(expired)

        #expect(try await repository.recoverable().map(\.id) == [stale.id])
    }

    @Test("startup recovery fails the records a quit left processing and keeps their audio", arguments: Kind.allCases)
    func failInterrupted(kind: Kind) async throws {
        let repository = try kind.make()
        let interrupted = Self.record(age: 10)
        let done = Self.record(status: .succeeded)
        let newer = Self.record(age: -5)
        try await repository.insert(interrupted)
        try await repository.insert(done)
        try await repository.insert(newer)

        // A dictation that began after the launch is under way, not interrupted.
        #expect(try await repository.failInterrupted(createdBefore: Self.now) == 1)

        let recovered = try await repository.record(id: interrupted.id)
        #expect(recovered?.status == .failed)
        #expect(recovered?.failure == DictationRecord.interruptedFailure)
        #expect(recovered?.audioURL == interrupted.audioURL)
        #expect(recovered?.hasAudio == true)
        #expect(try await repository.record(id: done.id) == done)
        #expect(try await repository.recoverable().map(\.id) == [newer.id])
        #expect(try await repository.failInterrupted(createdBefore: Self.now) == 0)
        #expect(try await repository.failInterrupted(createdBefore: Self.now.addingTimeInterval(60)) == 1)
    }

    @Test(
        "audioOlderThan lists the stored audio created before the cutoff, and expiring clears it",
        arguments: Kind.allCases)
    func audioRetention(kind: Kind) async throws {
        let repository = try kind.make()
        let day: TimeInterval = 86_400
        let old = Self.record(age: 8 * day)
        let fresh = Self.record(age: 6 * day)
        let noAudio = Self.record(age: 9 * day, audio: false)
        try await repository.insert(old)
        try await repository.insert(fresh)
        try await repository.insert(noAudio)

        let cutoff = Self.now.addingTimeInterval(-7 * day)
        #expect(try await repository.audioOlderThan(cutoff).map(\.id) == [old.id])

        try await repository.markAudioExpired(old.id)
        let expired = try await repository.record(id: old.id)
        #expect(expired?.audioExpired == true)
        #expect(expired?.audioURL == nil)
        #expect(expired?.hasAudio == false)
        #expect(try await repository.audioOlderThan(cutoff).isEmpty)
    }

    @Test("deleting removes one record, and deleting all keeps only the ones named", arguments: Kind.allCases)
    func deleting(kind: Kind) async throws {
        let repository = try kind.make()
        let records = (0..<4).map { Self.record(UUID(), age: Double($0)) }
        for record in records { try await repository.insert(record) }

        try await repository.delete(records[0].id)
        #expect(try await repository.page(offset: 0, limit: 10).map(\.id) == records.dropFirst().map(\.id))

        try await repository.deleteAll(keeping: [records[3].id])
        #expect(try await repository.page(offset: 0, limit: 10).map(\.id) == [records[3].id])

        try await repository.deleteAll()
        #expect(try await repository.page(offset: 0, limit: 10).isEmpty)
    }

    @Test("the change stream yields after each change, and not for a read", arguments: Kind.allCases)
    func changes(kind: Kind) async throws {
        let repository = try kind.make()
        var changes = repository.changes().makeAsyncIterator()
        let record = Self.record()

        try await repository.insert(record)
        _ = try await repository.page(offset: 0, limit: 10)
        #expect(await changes.next() != nil)

        var updated = record
        updated.status = .succeeded
        try await repository.update(updated)
        #expect(await changes.next() != nil)

        try await repository.delete(record.id)
        #expect(await changes.next() != nil)
    }
}

@Suite("GRDB history repository", .timeLimit(.minutes(1)))
struct GRDBHistoryRepositoryTests {
    /// The fields the spec asks a record to have, as columns.
    private static let specColumns: Set<String> = [
        "id", "createdAt", "durationMs", "status", "rawText", "cleanedText", "finalText", "asrProvider",
        "cleanerProvider", "fallbackReason", "appName", "bundleID", "urlHost", "category", "tone", "styleSource",
        "delivery", "audioPath", "audioExpired", "failure",
    ]

    private static func columns(of queue: DatabaseQueue) throws -> [String] {
        try queue.read { db in try db.columns(in: "dictations").map(\.name) }
    }

    @Test("migration v1 creates the table with every field of the spec")
    func migrationCreatesTable() throws {
        let queue = try DatabaseQueue()
        _ = try GRDBHistoryRepository(queue)

        #expect(Set(try Self.columns(of: queue)) == Self.specColumns)
        let applied = try queue.read { db in try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations") }
        #expect(applied == ["v1"])
    }

    @Test("running the migrations again changes nothing")
    func migrationsAreIdempotent() throws {
        let queue = try DatabaseQueue()
        _ = try GRDBHistoryRepository(queue)
        _ = try GRDBHistoryRepository(queue)

        let applied = try queue.read { db in try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations") }
        #expect(applied == ["v1"])
    }

    @Test("no column can hold context text: no text around the cursor, no selection, no screen text")
    func noContextTextColumns() throws {
        let queue = try DatabaseQueue()
        _ = try GRDBHistoryRepository(queue)

        let forbidden = ["context", "cursor", "selection", "selected", "ocr", "screen", "field", "before", "after"]
        for column in try Self.columns(of: queue) {
            for word in forbidden {
                #expect(!column.lowercased().contains(word), "\(column) looks like it holds context text")
            }
        }
    }

    @Test("a record survives closing and reopening the database file")
    func survivesReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "susurro-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "nested/History.sqlite")
        let record = HistoryRepositoryContractTests.record()

        do {
            let repository = try GRDBHistoryRepository(path: file.path)
            try await repository.insert(record)
        }
        let reopened = try GRDBHistoryRepository(path: file.path)

        #expect(try await reopened.record(id: record.id) == record)
        #expect(try await reopened.recoverable().map(\.id) == [record.id])
    }
}
