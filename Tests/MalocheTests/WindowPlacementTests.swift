import AppKit
import MalocheCore
import Testing

@testable import Maloche

/// The windows are built but never shown; each opens at its final size in the middle of its screen.
@MainActor @Suite struct WindowPlacementTests {
    private func expectCentered(_ window: NSWindow, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let placed = window.frame
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        #expect(
            window.frame == placed, "size changed after placing: \(placed) to \(window.frame)",
            sourceLocation: sourceLocation)
        let visible = try #require(window.screen, sourceLocation: sourceLocation).visibleFrame
        #expect(
            abs(window.frame.midX - visible.midX) <= 1 && abs(window.frame.midY - visible.midY) <= 1,
            "\(window.frame) in \(visible)", sourceLocation: sourceLocation)
        #expect(!window.isVisible, sourceLocation: sourceLocation)
    }

    @Test func welcomeOpensCentered() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let controller = WelcomeWindowController(model: model, isLoginItem: { false }, setLoginItem: { _ in })
        try expectCentered(controller.window)
    }

    @Test func settingsOpensCentered() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        try expectCentered(SettingsWindowController(model: model) { _ in }.window)
    }

    @Test func manageActivitiesOpensCentered() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        try expectCentered(ManageActivitiesWindowController(model: model).window)
    }
}
