import AppKit
import Testing

@testable import Maloche

/// A click on the icon while the panel shows closes or focuses it, otherwise the session or the action opens it.
@MainActor @Suite struct StatusItemClickTests {
    private let button = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    private let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)

    @Test func aClickOnTheIconWhileThePanelShowsIsHandledByTheApp() {
        #expect(CheckInPanelController.isIconClick(in: button, button: button, panelVisible: true))
    }

    @Test func aClickOnTheIconWithoutPanelGoesToTheStatusItem() {
        #expect(!CheckInPanelController.isIconClick(in: button, button: button, panelVisible: false))
    }

    @Test func clicksElsewhereAreNotIconClicks() {
        #expect(!CheckInPanelController.isIconClick(in: other, button: button, panelVisible: true))
        #expect(!CheckInPanelController.isIconClick(in: nil, button: nil, panelVisible: true))
    }
}
