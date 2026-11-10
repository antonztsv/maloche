import AppKit
import Foundation
import Testing
import WamaduCore

@testable import Wamadu

/// The chosen files lead to the preview or to a note; no panel or window is shown.
@MainActor @Suite struct DailyImportFlowTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "wamadu-flow-\(UUID().uuidString)")

    private func write(activities: String, timesheet: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(activities.utf8).write(to: folder.appending(path: "activities.json"))
        try Data(timesheet.utf8).write(to: folder.appending(path: "timesheet.json"))
    }

    @Test func aReadableFolderShowsThePreviewWithoutWriting() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(
            activities: #"[{"name": "acme - Design", "group": null, "archived": false, "lastUsed": null}]"#,
            timesheet: """
                [{"date": "2026-11-06", "activities": [{"activity": "acme - Design", "group": null, "duration": 900}],
                  "info": {"started": "2026-11-06T08:00:00+01:00", "ended": null, "total": 900}}]
                """)
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let flow = DailyImportFlow()

        flow.open([folder], model: model)
        let preview = try #require(flow.preview)
        #expect(flow.note == nil)
        #expect(preview.activityCount == 1)
        #expect(preview.dayCount == 1)
        #expect(try model.database.activities().count == 2, "nothing is written before Import")
        #expect(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
    }

    @Test func anUnreadableFileOrAnotherFolderShowsANote() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(activities: "[]", timesheet: "{")
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let flow = DailyImportFlow()

        flow.open([folder], model: model)
        #expect(flow.preview == nil)
        #expect(flow.note != nil)

        flow.note = nil
        flow.open([folder.appending(path: "activities.json")], model: model)
        #expect(flow.preview == nil)
        #expect(flow.note != nil)
    }
}
