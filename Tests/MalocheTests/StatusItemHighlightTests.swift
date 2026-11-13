import AppKit
import Testing

@testable import Maloche

/// The button is never in a window, the update notification is posted on a private center.
@MainActor @Suite struct StatusItemHighlightTests {
    @Test func theButtonIsHighlightedAgainAfterEachEventWhileThePanelShows() {
        let center = NotificationCenter()
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        var visible = true
        let highlight = StatusItemHighlight(button: button, center: center) { visible }
        highlight.apply()
        #expect(button.isHighlighted)

        // the click tracking of the button drops the highlight at mouse up
        button.highlight(false)
        center.post(name: NSApplication.didUpdateNotification, object: nil)
        #expect(button.isHighlighted)

        visible = false
        center.post(name: NSApplication.didUpdateNotification, object: nil)
        #expect(!button.isHighlighted)
    }
}
