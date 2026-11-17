import CoreGraphics

/// Geometry for the check-in panel and the windows. All rects are in Cocoa screen coordinates unless named otherwise.
public enum PanelPlacement {
    public static func screenIndex(containing windowBounds: CGRect, screens: [CGRect]) -> Int? {
        let areas = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(windowBounds)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    /// CGWindowList rects have their origin at the top left of the primary screen.
    public static func cocoaRect(fromWindowListRect rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The anchor is the status item's distance from the right edge of the full screen frame.
    public static func panelFrame(
        size: CGSize, anchorOffsetFromRight: CGFloat, screenFrame: CGRect, visibleFrame: CGRect, margin: CGFloat
    ) -> CGRect {
        let centeredX = screenFrame.maxX - anchorOffsetFromRight - size.width / 2
        let x = min(max(centeredX, visibleFrame.minX + margin), visibleFrame.maxX - margin - size.width)
        return CGRect(x: x, y: visibleFrame.maxY - margin - size.height, width: size.width, height: size.height)
    }

    /// The middle of the visible frame, not AppKit's center() which sits higher; a taller window keeps its top edge
    /// below the menu bar.
    public static func centeredOrigin(size: CGSize, visibleFrame: CGRect) -> CGPoint {
        let y = (visibleFrame.midY - size.height / 2).rounded(.down)
        return CGPoint(
            x: (visibleFrame.midX - size.width / 2).rounded(.down), y: min(y, visibleFrame.maxY - size.height))
    }

    /// Nil keeps a window that is on the active space and mostly on the active screen where the user put it; any
    /// other window moves to the middle of the active screen.
    public static func reopenedOrigin(
        frame: CGRect, onActiveSpace: Bool, screens: [CGRect], activeScreen: CGRect, activeVisibleFrame: CGRect
    ) -> CGPoint? {
        if onActiveSpace, let index = screenIndex(containing: frame, screens: screens), screens[index] == activeScreen {
            return nil
        }
        return centeredOrigin(size: frame.size, visibleFrame: activeVisibleFrame)
    }
}
