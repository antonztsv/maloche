import CoreGraphics
import Testing

@testable import MalocheCore

@Suite struct PanelPlacementTests {
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    @Test func picksScreenWithLargestOverlap() {
        let window = CGRect(x: -300, y: 100, width: 1000, height: 500)
        #expect(PanelPlacement.screenIndex(containing: window, screens: [primary, left]) == 0)
        let mostlyLeft = CGRect(x: -900, y: 100, width: 1000, height: 500)
        #expect(PanelPlacement.screenIndex(containing: mostlyLeft, screens: [primary, left]) == 1)
    }

    @Test func noScreenWhenWindowIsOffscreen() {
        let window = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        #expect(PanelPlacement.screenIndex(containing: window, screens: [primary, left]) == nil)
    }

    @Test func convertsWindowListRectToCocoaCoordinates() {
        let fromTop = CGRect(x: 10, y: 37, width: 200, height: 100)
        let cocoa = PanelPlacement.cocoaRect(fromWindowListRect: fromTop, primaryScreenHeight: 1117)
        #expect(cocoa == CGRect(x: 10, y: 980, width: 200, height: 100))
    }

    @Test func panelHangsCenteredUnderAnchor() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let frame = PanelPlacement.panelFrame(
            size: CGSize(width: 380, height: 200), anchorOffsetFromRight: 400, screenFrame: visible,
            visibleFrame: visible, margin: 6)
        #expect(frame == CGRect(x: 1138, y: 874, width: 380, height: 200))
    }

    @Test func anchorIsMeasuredFromScreenEdgeNotFromDock() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visible = CGRect(x: 0, y: 0, width: 1650, height: 1080)
        let frame = PanelPlacement.panelFrame(
            size: CGSize(width: 380, height: 200), anchorOffsetFromRight: 400, screenFrame: screen,
            visibleFrame: visible, margin: 6)
        #expect(frame.midX == 1328)
    }

    @Test func panelStaysInsideScreenNearRightEdge() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let frame = PanelPlacement.panelFrame(
            size: CGSize(width: 380, height: 200), anchorOffsetFromRight: 20, screenFrame: visible,
            visibleFrame: visible, margin: 6)
        #expect(frame.maxX == -6)
        #expect(frame.maxY == 1044)
    }

    @Test func panelStaysInsideScreenNearLeftEdge() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = PanelPlacement.panelFrame(
            size: CGSize(width: 380, height: 200), anchorOffsetFromRight: 790, screenFrame: visible,
            visibleFrame: visible, margin: 6)
        #expect(frame.minX == 6)
    }

    @Test func windowSitsInTheMiddleOfTheVisibleFrame() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let origin = PanelPlacement.centeredOrigin(size: CGSize(width: 560, height: 501), visibleFrame: visible)
        #expect(origin == CGPoint(x: -1240, y: 277))
    }

    @Test func aWindowTallerThanTheScreenKeepsItsTitleBarBelowTheMenuBar() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)
        let origin = PanelPlacement.centeredOrigin(size: CGSize(width: 640, height: 1000), visibleFrame: visible)
        #expect(origin == CGPoint(x: 400, y: -130))
    }
}
