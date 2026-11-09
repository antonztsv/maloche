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
            try db.create(table: "activity") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("lastUsedAt", .datetime)
            }
            try db.create(table: "block") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("activity", onDelete: .restrict).notNull()
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
                t.column("source", .text).notNull()
            }
        }
        return migrator
    }
}
