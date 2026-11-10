import AppKit
import Testing
import WamaduCore

@testable import Wamadu

/// The Manage Activities window is built but never shown, so no keystrokes of the user are taken.
@MainActor @Suite struct ManageActivitiesWindowTests {
    @Test func theWindowIsANormalResizableWindowOfTheBoardSize() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        _ = try model.database.createActivity(name: "Writing")
        let window = ManageActivitiesWindowController(model: model).window
        #expect(window.identifier == ManageActivitiesWindowController.identifier)
        #expect(window.title == "Manage Activities")
        #expect(window.styleMask.isSuperset(of: [.titled, .closable, .resizable]))
        #expect(try #require(window.contentView).frame.size == ManageActivitiesWindowController.size)
        #expect(window.contentMinSize == ManageActivitiesWindowController.minSize)
        #expect(!window.isVisible)
        #expect(NSApplication.shared.keyWindow == nil)
    }
}
