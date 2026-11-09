import Foundation
import GRDB

public struct AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    public static func open(at url: URL) throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(path: url.path(percentEncoded: false)))
    }

    public static func defaultURL(
        bundleIdentifier: String,
        applicationSupport: URL = .applicationSupportDirectory
    ) throws -> URL {
        let directory = applicationSupport.appending(path: bundleIdentifier, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "wamadu.sqlite")
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "customer") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique().collate(.nocase)
                t.column("colorIndex", .integer).notNull()
            }
            try db.create(table: "project") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.belongsTo("customer", onDelete: .restrict)
            }
            try db.create(table: "activity") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.belongsTo("project", onDelete: .restrict)
                t.belongsTo("customer", onDelete: .restrict)
                t.column("kind", .text).notNull().defaults(to: ActivityKind.regular.rawValue)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("lastUsedAt", .datetime)
                t.check(sql: "projectId IS NULL OR customerId IS NULL")
            }
            try db.create(
                indexOn: "activity", columns: ["kind"], options: .unique, condition: Column("kind") != "regular")
            try db.execute(
                sql: "INSERT INTO activity (name, kind) VALUES ('Break', 'break'), ('Private', 'private')")
            try db.create(table: "block") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("activity", onDelete: .restrict).notNull()
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("endedAt", .datetime).notNull()
                t.column("source", .text).notNull()
                t.check(sql: "endedAt > startedAt")
            }
            for event in ["INSERT", "UPDATE"] {
                try db.execute(
                    sql: """
                        CREATE TRIGGER block_no_overlap_\(event.lowercased()) BEFORE \(event) ON block
                        WHEN EXISTS (
                            SELECT 1 FROM block other
                            WHERE other.startedAt < NEW.endedAt AND other.endedAt > NEW.startedAt
                                AND other.id IS NOT NEW.id)
                        BEGIN SELECT RAISE(ABORT, 'block overlaps another block'); END
                        """)
            }
        }
        return migrator
    }
}
