import GRDB

/// The schema of the history database, one migration for each change. A migration that has run is never edited: a change
/// is a new migration.
enum HistoryMigrations {
    static let tableName = "dictations"

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: tableName) { table in
                table.primaryKey("id", .text)
                // Seconds since 1970 as a real number, so a date reads back exactly as it was written.
                table.column("createdAt", .double).notNull()
                table.column("durationMs", .integer).notNull()
                table.column("status", .text).notNull()
                table.column("rawText", .text)
                table.column("cleanedText", .text)
                table.column("finalText", .text)
                table.column("asrProvider", .text)
                table.column("cleanerProvider", .text)
                table.column("fallbackReason", .text)
                table.column("appName", .text)
                table.column("bundleID", .text)
                table.column("urlHost", .text)
                table.column("category", .text)
                table.column("tone", .text)
                table.column("styleSource", .text)
                table.column("delivery", .text)
                // The path of the stored audio, or null once it expired or when there is none.
                table.column("audioPath", .text)
                table.column("audioExpired", .boolean).notNull().defaults(to: false)
                // The name of the failure, never the text of an error.
                table.column("failure", .text)
            }
            try db.create(index: "dictationsByCreatedAt", on: tableName, columns: ["createdAt", "id"])
            try db.create(index: "dictationsByStatus", on: tableName, columns: ["status"])
        }
        return migrator
    }
}
