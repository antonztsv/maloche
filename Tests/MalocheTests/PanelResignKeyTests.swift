import AppKit
import MalocheCore
import Testing

@testable import Maloche

/// The panel is built but never shown; losing the key status is posted by hand.
@MainActor @Suite struct PanelResignKeyTests {
    @Test func aClickOutsideClosesTheDashboard() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let controller = CheckInPanelController(model: model)
        model.presenter = controller
        model.showDashboard(Period(.day, containing: Date(), calendar: model.calendar))
        #expect(model.panel != nil)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: controller.panel)

        #expect(model.panel == nil)
        #expect(!controller.panel.isVisible)
    }

    /// The delete confirmation is a sheet that takes the key status, the dashboard behind it stays.
    @Test func aSheetTakingTheKeyStatusKeepsThePanel() {
        #expect(CheckInPanelController.closesOnResignKey(sheetAttached: false))
        #expect(!CheckInPanelController.closesOnResignKey(sheetAttached: true))
    }
}
