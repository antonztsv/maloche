import CoreGraphics

/// Geometry for the check-in panel. All rects are in Cocoa screen coordinates unless named otherwise.
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

    public static func panelFrame(
        size: CGSize, anchorOffsetFromRight: CGFloat, visibleFrame: CGRect, margin: CGFloat
    ) -> CGRect {
        let centeredX = visibleFrame.maxX - anchorOffsetFromRight - size.width / 2
        let x = min(max(centeredX, visibleFrame.minX + margin), visibleFrame.maxX - margin - size.width)
        return CGRect(x: x, y: visibleFrame.maxY - margin - size.height, width: size.width, height: size.height)
    }
}
