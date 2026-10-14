import Domain
import Foundation
import GRDB

/// The dictation history in a SQLite database. All access goes through one `DatabaseQueue`, so the calls are serialized
/// and a change is visible to the next read.
public final class GRDBHistoryRepository: HistoryRepository {
    private let queue: DatabaseQueue

    /// Opens the history on a queue and brings its schema up to date. Pass an in-memory queue in tests.
    public init(_ queue: DatabaseQueue) throws {
        self.queue = queue
        try HistoryMigrations.migrator().migrate(queue)
    }

    /// Opens the history in the file at `path`, creating the file and the folders above it when they are not there.
    public convenience init(path: String) throws {
        let folder = URL(filePath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try self.init(DatabaseQueue(path: path))
    }

    // MARK: HistoryRepository

    public func insert(_ record: DictationRecord) async throws {
        try await queue.write { db in
            let exists = try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM dictations WHERE id = ?)", arguments: [record.id.uuidString])
            guard exists != true else { throw HistoryError.duplicateRecord(record.id) }
            try db.execute(
                sql: """
                    INSERT INTO dictations (\(Self.columns.joined(separator: ", ")))
                    VALUES (\(Self.columns.map { _ in "?" }.joined(separator: ", ")))
                    """,
                arguments: StatementArguments(Self.values(of: record)))
        }
    }

    public func update(_ record: DictationRecord) async throws {
        try await queue.write { db in
            let assignments = Self.columns.dropFirst().map { "\($0) = ?" }.joined(separator: ", ")
            let values = Self.values(of: record)
            try db.execute(
                sql: "UPDATE dictations SET \(assignments) WHERE id = ?",
                arguments: StatementArguments(Array(values.dropFirst()) + [record.id.uuidString]))
            guard db.changesCount > 0 else { throw HistoryError.recordNotFound(record.id) }
        }
    }

    public func record(id: UUID) async throws -> DictationRecord? {
        try await queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM dictations WHERE id = ?", arguments: [id.uuidString])
                .flatMap(Self.record(from:))
        }
    }

    public func page(offset: Int, limit: Int) async throws -> [DictationRecord] {
        guard limit > 0 else { return [] }
        return try await queue.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM dictations ORDER BY createdAt DESC, id DESC LIMIT ? OFFSET ?",
                arguments: [limit, max(offset, 0)]
            ).compactMap(Self.record(from:))
        }
    }

    public func recoverable() async throws -> [DictationRecord] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM dictations WHERE status = ? AND audioPath IS NOT NULL AND audioExpired = 0
                    ORDER BY createdAt DESC, id DESC
                    """,
                arguments: [DictationStatus.processing.rawValue]
            ).compactMap(Self.record(from:))
        }
    }

    public func failInterrupted(createdBefore launch: Date) async throws -> Int {
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE dictations SET status = ?, failure = ? WHERE status = ? AND createdAt < ?",
                arguments: [
                    DictationStatus.failed.rawValue, DictationRecord.interruptedFailure,
                    DictationStatus.processing.rawValue, launch.timeIntervalSince1970,
                ])
            return db.changesCount
        }
    }

    public func audioOlderThan(_ cutoff: Date) async throws -> [DictationRecord] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM dictations WHERE audioPath IS NOT NULL AND audioExpired = 0 AND createdAt < ?
                    ORDER BY createdAt DESC, id DESC
                    """,
                arguments: [cutoff.timeIntervalSince1970]
            ).compactMap(Self.record(from:))
        }
    }

    public func markAudioExpired(_ id: UUID) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE dictations SET audioExpired = 1, audioPath = NULL WHERE id = ?",
                arguments: [id.uuidString])
            guard db.changesCount > 0 else { throw HistoryError.recordNotFound(id) }
        }
    }

    public func delete(_ id: UUID) async throws {
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM dictations WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func deleteAll(keeping: Set<UUID>) async throws {
        try await queue.write { db in
            guard !keeping.isEmpty else {
                try db.execute(sql: "DELETE FROM dictations")
                return
            }
            let marks = keeping.map { _ in "?" }.joined(separator: ", ")
            try db.execute(
                sql: "DELETE FROM dictations WHERE id NOT IN (\(marks))",
                arguments: StatementArguments(keeping.map(\.uuidString)))
        }
    }

    public func changes() -> AsyncStream<Void> {
        let queue = queue
        return AsyncStream { continuation in
            let cancellable = DatabaseRegionObservation(tracking: Table(HistoryMigrations.tableName))
                .start(in: queue, onError: { _ in continuation.finish() }, onChange: { _ in continuation.yield() })
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    // MARK: Rows

    /// The columns in the order `values(of:)` lists their values; the id comes first.
    private static let columns = [
        "id", "createdAt", "durationMs", "status", "rawText", "cleanedText", "finalText", "asrProvider",
        "cleanerProvider", "fallbackReason", "appName", "bundleID", "urlHost", "category", "tone", "styleSource",
        "delivery", "audioPath", "audioExpired", "failure",
    ]

    private static func values(of record: DictationRecord) -> [(any DatabaseValueConvertible)?] {
        let components = record.duration.components
        let milliseconds = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        let values: [(any DatabaseValueConvertible)?] = [
            record.id.uuidString, record.createdAt.timeIntervalSince1970, milliseconds, record.status.rawValue,
            record.rawText, record.cleanedText, record.finalText, record.asrProvider?.rawValue,
            record.cleanerProvider, record.fallbackReason, record.appName, record.bundleID, record.urlHost,
            record.category, record.tone, record.styleSource, record.delivery?.rawValue, record.audioURL?.path,
            record.audioExpired, record.failure,
        ]
        return values
    }

    /// The record a row holds, or nil for one that is not a record this version can read, such as one with a status a
    /// newer version of the app wrote. Such a row is left out of the lists and is not touched.
    private static func record(from row: Row) -> DictationRecord? {
        guard let id = UUID(uuidString: row["id"]), let status = DictationStatus(rawValue: row["status"]) else {
            return nil
        }
        let milliseconds: Int64 = row["durationMs"]
        return DictationRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: row["createdAt"]),
            duration: .milliseconds(milliseconds),
            status: status,
            rawText: row["rawText"],
            cleanedText: row["cleanedText"],
            finalText: row["finalText"],
            asrProvider: (row["asrProvider"] as String?).map(ASRProviderID.init),
            cleanerProvider: row["cleanerProvider"],
            fallbackReason: row["fallbackReason"],
            appName: row["appName"],
            bundleID: row["bundleID"],
            urlHost: row["urlHost"],
            category: row["category"],
            tone: row["tone"],
            styleSource: row["styleSource"],
            delivery: (row["delivery"] as String?).flatMap(DictationDelivery.init(rawValue:)),
            audioURL: (row["audioPath"] as String?).map { URL(filePath: $0) },
            audioExpired: row["audioExpired"],
            failure: row["failure"]
        )
    }
}
