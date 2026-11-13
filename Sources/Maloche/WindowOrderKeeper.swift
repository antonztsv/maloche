import AppKit

/// A click on the menu bar icon must not send the app's windows back: when the app loses the active state around
/// such a click, the windows that were in front come back to the front.
@MainActor
final class WindowOrderKeeper {
    /// How far apart the click and the deactivation may be to belong together.
    static let window: TimeInterval = 0.5

    private let restore: ([NSWindow]) -> Void
    private var clickedAt: Date?
    private var resigned: (windows: [NSWindow], at: Date)?

    init(restore: @escaping ([NSWindow]) -> Void) {
        self.restore = restore
    }

    func statusItemClicked(at date: Date) {
        clickedAt = date
        restoreIfTogether()
    }

    /// `frontWindows` are the visible windows of the app, front to back, panels excluded.
    func appResigned(frontWindows: [NSWindow], at date: Date) {
        resigned = (frontWindows, date)
        restoreIfTogether()
    }

    private func restoreIfTogether() {
        guard let clickedAt, let resigned, abs(resigned.at.timeIntervalSince(clickedAt)) < Self.window else { return }
        self.clickedAt = nil
        self.resigned = nil
        if !resigned.windows.isEmpty { restore(resigned.windows) }
    }
}

extension NSWindow {
    /// A window the user opened comes to the front and becomes key, and stays in front when the system declines the
    /// activation.
    func bringToFront() {
        // cooperative activation, a plain activate() from a nonactivating panel is declined while another app is active
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            NSRunningApplication.current.activate(from: front)
        } else {
            NSApp.activate()
        }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}
