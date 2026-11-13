import Foundation
import GRDB
import Testing

@testable import MalocheCore

/// A temporary folder, deleted with the value.
final class TemporaryFolder: @unchecked Sendable {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "maloche-tests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

    deinit { try? FileManager.default.removeItem(at: url) }

    var names: [String] {
        get throws { try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).sorted() }
    }
}

/// Backups are complete copies made with SQLite's online backup, restoring one replaces the content.
@Suite struct BackupStoreTests {
    private let folder: TemporaryFolder
    private let database: AppDatabase

    init() throws {
        folder = try TemporaryFolder()
        database = try AppDatabase.inMemory()
        let writing = try database.createActivity(name: "Writing")
        try database.insert(
            block: Block(
                activityId: writing.id!, startedAt: Fixture.at("09:00"), endedAt: Fixture.at("09:30"),
                source: .checkIn))
    }

    private func backUp(at time: String, keep: Int = 30) throws -> Backup {
        try database.backUp(to: folder.url, at: Fixture.at(time), keep: keep, calendar: Fixture.berlin)
    }

    private func names(_ database: AppDatabase) throws -> [String] {
        try database.activities().map(\.name).sorted()
    }

    @Test func aBackupIsACompleteDatabaseWithTheSameRows() throws {
        let backup = try backUp(at: "10:00")
        #expect(backup.url.lastPathComponent == "maloche 2026-11-09 10.00.sqlite")
        #expect(backup.date == Fixture.at("10:00"))
        #expect(try folder.names == ["maloche 2026-11-09 10.00.sqlite"])

        let copy = try AppDatabase.open(at: backup.url)
        #expect(try names(copy) == ["Break", "Private", "Writing"])
        #expect(
            try copy.blocks(in: Fixture.span("00:00", "23:59")) == database.blocks(in: Fixture.span("00:00", "23:59")))
        #expect(try copy.dbQueue.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") } == "ok")
    }

    @Test func namesSortByTimeAndOtherFilesAreLeftOut() throws {
        for time in ["2026-11-10 08:05", "09:00", "2026-12-01 07:30", "2026-11-09 23:59"] {
            _ = try backUp(at: time)
        }
        for name in [
            "notes.txt", "maloche.sqlite", "Maloche 2026-11-01 09.00.sqlite", "maloche 2026-11-01 09.00.sqlite.bak",
            "maloche 2026-11-01 9.00.sqlite",
        ] {
            try Data("x".utf8).write(to: folder.url.appending(path: name))
        }

        let backups = Backup.all(in: folder.url, calendar: Fixture.berlin)
        #expect(
            backups.map(\.url.lastPathComponent) == [
                "maloche 2026-11-09 09.00.sqlite", "maloche 2026-11-09 23.59.sqlite", "maloche 2026-11-10 08.05.sqlite",
                "maloche 2026-12-01 07.30.sqlite",
            ])
        #expect(
            backups.map(\.date) == ["09:00", "23:59", "2026-11-10 08:05", "2026-12-01 07:30"].map(Fixture.at))
        #expect(Backup.all(in: folder.url.appending(path: "elsewhere"), calendar: Fixture.berlin).isEmpty)
    }

    @Test func rotationKeepsTheNewestAndLeavesOtherFilesAlone() throws {
        let foreign = ["notes.txt", "maloche.sqlite", "maloche 2026-11-01 09.00.sqlite.bak"]
        for name in foreign { try Data("x".utf8).write(to: folder.url.appending(path: name)) }

        for time in ["08:00", "09:00", "10:00", "11:00"] { _ = try backUp(at: time, keep: 3) }
        #expect(
            try folder.names
                == (foreign + [
                    "maloche 2026-11-09 09.00.sqlite", "maloche 2026-11-09 10.00.sqlite",
                    "maloche 2026-11-09 11.00.sqlite",
                ]).sorted())

        // after the clock went back, the backups dated after the new one stay
        _ = try backUp(at: "07:00", keep: 3)
        #expect(
            try folder.names
                == (foreign + [
                    "maloche 2026-11-09 07.00.sqlite", "maloche 2026-11-09 09.00.sqlite",
                    "maloche 2026-11-09 10.00.sqlite", "maloche 2026-11-09 11.00.sqlite",
                ]).sorted())
    }

    @Test func backupsDatedAheadAreLeftAloneAndDoNotCount() throws {
        for time in ["2030-01-01 00:00", "2030-01-02 00:00", "08:00", "09:00", "10:00", "11:00"] {
            _ = try backUp(at: time, keep: 3)
        }
        #expect(
            try folder.names == [
                "maloche 2026-11-09 09.00.sqlite", "maloche 2026-11-09 10.00.sqlite", "maloche 2026-11-09 11.00.sqlite",
                "maloche 2030-01-01 00.00.sqlite", "maloche 2030-01-02 00.00.sqlite",
            ])
    }

    @Test func aMissingFolderIsCreatedOnlyInsideAnExistingOne() throws {
        let inside = folder.url.appending(path: "Backups")
        _ = try database.backUp(to: inside, at: Fixture.at("10:00"), keep: 30, calendar: Fixture.berlin)
        #expect(Backup.all(in: inside, calendar: Fixture.berlin).count == 1)

        let unmounted = folder.url.appending(path: "Volume/Backups")
        #expect(throws: (any Error).self) {
            try database.backUp(to: unmounted, at: Fixture.at("10:00"), keep: 30, calendar: Fixture.berlin)
        }
        #expect(!FileManager.default.fileExists(atPath: unmounted.path(percentEncoded: false)))
    }

    @Test func restoringReplacesTheContentAndKeepsTheConnection() throws {
        let backup = try backUp(at: "10:00")
        let reading = try database.createActivity(name: "Reading")
        try database.insert(
            block: Block(
                activityId: reading.id!, startedAt: Fixture.at("10:00"), endedAt: Fixture.at("11:00"),
                source: .checkIn))
        let before = try Data(contentsOf: backup.url)

        let restorable = try AppDatabase.readBackup(at: backup.url, calendar: Fixture.berlin)
        #expect(restorable.date == Fixture.at("10:00"))
        #expect(try names(database) == ["Break", "Private", "Reading", "Writing"], "reading changes nothing")

        try database.restore(restorable)
        #expect(try names(database) == ["Break", "Private", "Writing"])
        #expect(try database.blocks(in: Fixture.span("00:00", "23:59")).map(\.endedAt) == [Fixture.at("09:30")])
        #expect(try Data(contentsOf: backup.url) == before, "the backup file is only read")
        _ = try database.createActivity(name: "After")
        #expect(try names(database) == ["After", "Break", "Private", "Writing"])
    }

    @Test func anOlderBackupIsMigratedBeforeItReplacesTheContent() throws {
        let backup = try backUp(at: "10:00")
        var newer = AppDatabase.migrator
        newer.registerMigration("v2") { db in
            try db.create(table: "note") { t in t.column("text", .text) }
        }

        try database.restore(AppDatabase.readBackup(at: backup.url, calendar: Fixture.berlin, migrator: newer))
        let applied = try database.dbQueue.read { db in try newer.appliedMigrations(db) }
        #expect(applied == ["v1", "v2"])
        #expect(try database.dbQueue.read { try $0.tableExists("note") })
        #expect(try names(database) == ["Break", "Private", "Writing"])
    }

    @Test func aFileThatIsNoMalocheBackupIsRejected() throws {
        let text = folder.url.appending(path: "maloche 2026-11-09 08.00.sqlite")
        try Data("not a database".utf8).write(to: text)

        let foreign = folder.url.appending(path: "other.sqlite")
        try DatabaseQueue(path: foreign.path(percentEncoded: false)).write { db in
            try db.execute(sql: "CREATE TABLE customer (id INTEGER); CREATE TABLE block (id INTEGER)")
        }

        let future = folder.url.appending(path: "future.sqlite")
        let futureQueue = try DatabaseQueue(path: future.path(percentEncoded: false))
        try AppDatabase.migrator.migrate(futureQueue)
        try futureQueue.write { db in try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('v99')") }
        try futureQueue.close()

        let missingTable = folder.url.appending(path: "missing.sqlite")
        let missingQueue = try DatabaseQueue(path: missingTable.path(percentEncoded: false))
        try AppDatabase.migrator.migrate(missingQueue)
        try missingQueue.write { db in try db.drop(table: "block") }
        try missingQueue.close()

        for url in [text, foreign, future, missingTable, folder.url.appending(path: "nothing.sqlite")] {
            let before = try? Data(contentsOf: url)
            #expect(throws: MalocheError.notABackup, "\(url.lastPathComponent)") {
                try AppDatabase.readBackup(at: url, calendar: Fixture.berlin)
            }
            #expect((try? Data(contentsOf: url)) == before)
        }
        #expect(try names(database) == ["Break", "Private", "Writing"])
    }
}
