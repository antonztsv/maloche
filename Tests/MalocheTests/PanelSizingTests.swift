import AppKit
import SwiftUI
import Testing

@testable import Maloche

/// The panel is built but never shown; only its controller sizes it, so a fold animates instead of jumping.
@MainActor @Suite struct PanelSizingTests {
    @Observable final class Content {
        var tall = false
    }

    struct Block: View {
        let content: Content
        var body: some View { Rectangle().frame(width: 200, height: content.tall ? 300 : 100) }
    }

    @Test func contentThatGrowsLeavesThePanelFrameToTheController() {
        let content = Content()
        let panel = CheckInPanel()
        let hosting = CheckInPanelController.hostingView(Block(content: content))
        panel.glass.contentView = hosting
        panel.setFrame(NSRect(x: 100, y: 500, width: 200, height: 100), display: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        content.tall = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(panel.frame == NSRect(x: 100, y: 500, width: 200, height: 100))
        #expect(hosting.fittingSize == NSSize(width: 200, height: 300))
        #expect(!panel.isVisible)
    }
}
