import AppKit

extension NSWindow {
    /// A window the user opened comes to the front and takes the keyboard; the app shows in the Dock while it is open.
    func bringToFront() {
        placeOnActiveScreen()
        NSApp.setActivationPolicy(.regular)
        // without a Dock icon a plain activate() is often declined
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// A visible titled window other than panels (the status bar window is borderless) and the closing one.
    static func hasNormalWindow(in windows: [NSWindow], closing: NSWindow?) -> Bool {
        windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) && $0 !== closing }
    }

    static func activationPolicy(showInDock: Bool, hasNormalWindow: Bool) -> NSApplication.ActivationPolicy {
        showInDock || hasNormalWindow ? .regular : .accessory
    }

    static var showInDock = false

    /// Applies the policy for the Dock setting and the windows open, ignoring a window that is closing.
    static func updateActivationPolicy(closing: NSWindow? = nil) {
        followClosing()
        let policy = activationPolicy(
            showInDock: showInDock, hasNormalWindow: hasNormalWindow(in: NSApp.windows, closing: closing))
        NSApp.setActivationPolicy(policy)
    }

    private static var closeObserver: NSObjectProtocol?

    private static func followClosing() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            let closing = ObjectIdentifier(note.object as AnyObject)
            MainActor.assumeIsolated {
                guard let window = NSApp.windows.first(where: { ObjectIdentifier($0) == closing }),
                    !(window is NSPanel)
                else { return }
                updateActivationPolicy(closing: window)
            }
        }
    }
}
