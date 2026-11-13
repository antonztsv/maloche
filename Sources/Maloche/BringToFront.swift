import AppKit

extension NSWindow {
    /// A window the user opened comes to the front and becomes key; the app shows in the Dock while it is open.
    func bringToFront() {
        NSWindow.followClosing()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    /// `.regular` while a visible window other than panels and the closing one remains, else `.accessory`.
    static func activationPolicy(for windows: [NSWindow], closing: NSWindow?) -> NSApplication.ActivationPolicy {
        windows.contains { $0.isVisible && !($0 is NSPanel) && $0 !== closing } ? .regular : .accessory
    }

    private static var closeObserver: NSObjectProtocol?

    private static func followClosing() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            let closing = ObjectIdentifier(note.object as AnyObject)
            MainActor.assumeIsolated {
                let windows = NSApp.windows
                guard let closing = windows.first(where: { ObjectIdentifier($0) == closing }), !(closing is NSPanel)
                else { return }
                NSApp.setActivationPolicy(activationPolicy(for: NSApp.windows, closing: closing))
            }
        }
    }
}
