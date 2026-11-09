import Foundation
import GRDB
import Testing

@testable import WamaduCore

@Suite struct AppDatabaseTests {
    private func insertActivity(_ db: Database, name: String) throws -> Int64 {
        try db.execute(sql: "INSERT INTO activity (name) VALUES (?)", arguments: [name])
        return db.lastInsertedRowID
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "AppDatabaseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func inMemoryDatabaseMigratesToV1() throws {
        let database = try AppDatabase.inMemory()
        let applied = try database.dbQueue.read { db in try AppDatabase.migrator.appliedMigrations(db) }
        let completed = try database.dbQueue.read { db in try AppDatabase.migrator.hasCompletedMigrations(db) }
        #expect(applied == ["v1"])
        #expect(completed)
    }

    @Test func insertsAndReadsActivityAndBlock() throws {
        let database = try AppDatabase.inMemory()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1_800)

        try database.dbQueue.write { db in
            let activityId = try insertActivity(db, name: "Writing")
            try db.execute(
                sql: #"INSERT INTO block (activityId, start, "end", source) VALUES (?, ?, ?, ?)"#,
                arguments: [activityId, start, end, "checkIn"])
        }

        let (activityRow, blockRow) = try database.dbQueue.read { db in
            (try Row.fetchOne(db, sql: "SELECT * FROM activity"), try Row.fetchOne(db, sql: "SELECT * FROM block"))
        }
        let activity = try #require(activityRow)
        #expect(activity["name"] == "Writing")
        #expect(activity["archived"] == false)
        #expect((activity["lastUsedAt"] as Date?) == nil)

        let block = try #require(blockRow)
        #expect(block["activityId"] == (activity["id"] as Int64))
        #expect(block["start"] == start)
        #expect(block["end"] == end)
        #expect(block["source"] == "checkIn")
    }

    @Test func deletingActivityWithBlocksFails() throws {
        let database = try AppDatabase.inMemory()
        try database.dbQueue.write { db in
            let activityId = try insertActivity(db, name: "Writing")
            let start = Date(timeIntervalSince1970: 1_700_000_000)
            try db.execute(
                sql: #"INSERT INTO block (activityId, start, "end", source) VALUES (?, ?, ?, ?)"#,
                arguments: [activityId, start, start.addingTimeInterval(60), "checkIn"])

            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "DELETE FROM activity WHERE id = ?", arguments: [activityId])
            }
        }
    }

    @Test func reopeningFileDatabaseKeepsData() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "wamadu.sqlite")

        do {
            let database = try AppDatabase.open(at: url)
            try database.dbQueue.write { db in _ = try insertActivity(db, name: "Writing") }
        }

        let reopened = try AppDatabase.open(at: url)
        let applied = try reopened.dbQueue.read { db in try AppDatabase.migrator.appliedMigrations(db) }
        let names = try reopened.dbQueue.read { db in try String.fetchAll(db, sql: "SELECT name FROM activity") }
        #expect(applied == ["v1"])
        #expect(names == ["Writing"])
    }

    @Test func defaultURLUsesBundleIdentifierFolder() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let url = try AppDatabase.defaultURL(bundleIdentifier: "com.example.test", applicationSupport: base)

        #expect(url == base.appending(path: "com.example.test").appending(path: "wamadu.sqlite"))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
