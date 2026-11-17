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

    private func windows() throws -> [NSWindow] {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        return [
            WelcomeWindowController(model: model, isLoginItem: { false }, setLoginItem: { _ in }).window,
            SettingsWindowController(model: model) { _ in }.window,
            ManageActivitiesWindowController(model: model).window,
        ]
    }

    /// Opening a window that sits on another space brings it to the active space instead of switching there.
    @Test func everyWindowMovesToTheActiveSpace() throws {
        for window in try windows() {
            #expect(window.collectionBehavior.contains(.moveToActiveSpace), "\(window.title)")
        }
    }

    @Test func aWindowLeftOnAnotherScreenComesBackToTheMiddleOfTheActiveOne() throws {
        for window in try windows() {
            window.setFrameOrigin(NSPoint(x: 50_000, y: 50_000))
            window.placeOnActiveScreen()
            let visible = try #require(window.screen).visibleFrame
            #expect(abs(window.frame.midX - visible.midX) <= 1 && abs(window.frame.midY - visible.midY) <= 1)
            let placed = window.frame
            window.placeOnActiveScreen()
            #expect(window.frame == placed)
            #expect(!window.isVisible)
        }
    }
}
