import AppKit
import MalocheCore

extension NSScreen {
    /// The screen with the frontmost window, else the main screen.
    static var active: NSScreen? { withFrontmostWindow() ?? main ?? screens.first }

    /// Window bounds and owner are readable without the screen recording permission, titles are not needed.
    private static func withFrontmostWindow() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let info = list.first(where: {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
            }),
            let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            let primaryHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        let window = PanelPlacement.cocoaRect(fromWindowListRect: bounds, primaryScreenHeight: primaryHeight)
        let screens = NSScreen.screens
        return PanelPlacement.screenIndex(containing: window, screens: screens.map(\.frame)).map { screens[$0] }
    }
}

extension NSWindow {
    /// Call once the window has its final size.
    func centerOnActiveScreen() {
        guard let visible = NSScreen.active?.visibleFrame else { return }
        setFrameOrigin(PanelPlacement.centeredOrigin(size: frame.size, visibleFrame: visible))
    }

    /// Before it comes to the front, a window on another space or screen moves to the middle of the active screen.
    func placeOnActiveScreen() {
        guard let screen = NSScreen.active,
            let origin = PanelPlacement.reopenedOrigin(
                frame: frame, onActiveSpace: isOnActiveSpace, screens: NSScreen.screens.map(\.frame),
                activeScreen: screen.frame, activeVisibleFrame: screen.visibleFrame)
        else { return }
        setFrameOrigin(origin)
    }
}
