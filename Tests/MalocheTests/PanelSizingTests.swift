import AppKit
import MalocheCore
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

    /// The top edge of the highest element on screen, where SwiftUI's layout put it.
    private func contentTop(_ element: Any) -> CGFloat {
        let node = element as AnyObject
        let children = node.accessibilityChildren?() as? [Any] ?? []
        return children.map(contentTop).max() ?? node.accessibilityFrame?().maxY ?? -.infinity
    }

    /// A fold resizes the panel toward the content's height; the content above the fold stays where it is, also while
    /// it is still taller than the panel.
    @Test(arguments: [-120.0, 120.0])
    func resizingThePanelLeavesTheContentAtItsTop(offset: CGFloat) throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        model.showDashboard(Period(.day, containing: .now, calendar: .current))
        let panel = CheckInPanel()
        let hosting = CheckInPanelController.hostingView(
            PanelView(model: model, onResize: {}).environment(\.accessibilityEnabled, true))
        panel.glass.contentView = hosting
        let size = hosting.fittingSize
        let top: CGFloat = 900
        let target = NSRect(x: 100, y: top - size.height, width: size.width, height: size.height)
        func inset() -> CGFloat {
            hosting.layoutSubtreeIfNeeded()
            return panel.frame.maxY - contentTop(hosting)
        }
        panel.setFrame(target, display: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let fitted = inset()
        let fittedFrame = panel.frame
        panel.setFrame(target.insetBy(dx: 0, dy: -offset / 2).offsetBy(dx: 0, dy: -offset / 2), display: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        var insets = [inset()]
        var frames = [panel.frame]

        panel.setFrame(target, duration: DashboardList.foldDuration)
        let start = Date()
        while Date().timeIntervalSince(start) < 0.4 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            insets.append(inset())
            frames.append(panel.frame)
        }

        #expect(Set(insets) == [fitted])
        #expect(Set(frames.map(\.maxY)) == [fittedFrame.maxY])
        #expect(Set(frames.map(\.height)).count > 5)
        #expect(frames.last == fittedFrame)
        #expect(!panel.isVisible)
    }
}

/// When the panel height follows its content with a motion, and how the step timer ends.
@MainActor @Suite struct PanelResizeMotionTests {
    private let fold = DashboardList.foldDuration

    @Test func onlyAFoldJustMadeAnimatesTheHeight() {
        #expect(CheckInPanelController.resizeDuration(foldedAt: 10, now: 10.02, reduceMotion: false) == fold)
        #expect(CheckInPanelController.resizeDuration(foldedAt: nil, now: 10, reduceMotion: false) == 0)
        #expect(CheckInPanelController.resizeDuration(foldedAt: 10, now: 10.02, reduceMotion: true) == 0)
        #expect(CheckInPanelController.resizeDuration(foldedAt: 10, now: 12, reduceMotion: false) == 0)
    }

    private let start = NSRect(x: 100, y: 500, width: 380, height: 200)
    private let target = NSRect(x: 100, y: 400, width: 380, height: 300)

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @Test func aFrameAlreadyReachedStartsNoSteps() {
        let panel = CheckInPanel()
        panel.setFrame(start, display: true)
        panel.setFrame(start, duration: fold)
        panel.setFrame(target, display: true)
        wait(0.4)
        #expect(panel.frame == target)
    }

    @Test func theSameTargetKeepsARunningMotion() {
        let panel = CheckInPanel()
        panel.setFrame(start, display: true)
        panel.setFrame(target, duration: fold)
        wait(0.05)
        panel.setFrame(target, duration: 0)
        #expect(panel.frame != target)
        wait(0.4)
        #expect(panel.frame == target)
    }

    @Test func hidingStopsTheSteps() {
        let panel = CheckInPanel()
        panel.setFrame(start, display: true)
        panel.setFrame(target, duration: fold)
        panel.orderOut(nil)
        wait(0.4)
        #expect(panel.frame == start)
        #expect(!panel.isVisible)
    }
}
