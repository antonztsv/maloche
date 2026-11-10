import AppKit
import Foundation
import Testing
import WamaduCore

@testable import Wamadu

/// The chosen file leads to the confirmation or to a note; no panel or window is shown.
@MainActor @Suite struct RestoreFlowTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "wamadu-restore-\(UUID().uuidString)")

    private func hasReading(_ model: AppModel) throws -> Bool {
        try model.database.activities().contains { $0.name == "Reading" }
    }

    @Test func aBackupIsRestoredOnlyAfterTheConfirmation() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try AppModel(database: .inMemory(), stateURL: nil, backups: folder)
        model.backUpNow()
        let saved = try #require(Backup.all(in: folder, calendar: model.calendar).first)
        _ = try model.database.createActivity(name: "Reading")
        let flow = RestoreFlow()

        flow.open(saved.url, model: model)
        let backup = try #require(flow.backup)
        #expect(flow.note == nil)
        #expect(try hasReading(model), "nothing changes before the confirmation")

        flow.restore(backup, model: model)
        #expect(flow.backup == nil)
        #expect(flow.note == nil)
        #expect(try !hasReading(model))
        #expect(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
    }

    @Test func anotherFileShowsANoteAndChangesNothing() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "notes.txt")
        try Data("notes".utf8).write(to: file)
        let model = try AppModel(database: .inMemory(), stateURL: nil, backups: folder)
        _ = try model.database.createActivity(name: "Reading")
        let flow = RestoreFlow()

        flow.open(file, model: model)
        #expect(flow.backup == nil)
        #expect(flow.note != nil)
        #expect(try hasReading(model))
    }

    @Test func aRestoreThatDoesNotGoThroughShowsANote() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try AppModel(database: .inMemory(), stateURL: nil, backups: folder).backUpNow()
        let saved = try #require(Backup.all(in: folder, calendar: .current).first)
        let withoutFolder = try AppModel(database: .inMemory(), stateURL: nil)
        _ = try withoutFolder.database.createActivity(name: "Reading")
        let flow = RestoreFlow()

        flow.open(saved.url, model: withoutFolder)
        flow.restore(try #require(flow.backup), model: withoutFolder)
        #expect(flow.note != nil)
        #expect(try hasReading(withoutFolder))
    }

    @Test func folderNamesReadLikeTheFinder() {
        let home = "/Users/sample"
        #expect(
            BackupSettingsView.folderName(
                "/Users/sample/Library/Mobile Documents/com~apple~CloudDocs/Backups/wamadu", home: home)
                == "iCloud Drive / Backups / wamadu")
        #expect(
            BackupSettingsView.folderName(
                "/Users/sample/Library/Application Support/io.github.antonztsv.wamadu/Backups", home: home)
                == "Library / Application Support / io.github.antonztsv.wamadu / Backups")
        #expect(BackupSettingsView.folderName("/Volumes/Archive/wamadu/", home: home) == "Archive / wamadu")
        #expect(BackupSettingsView.folderName("/Users/sampler/Backups", home: home) == "Users / sampler / Backups")
    }
}
