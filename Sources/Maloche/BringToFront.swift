import AppKit

extension NSWindow {
    /// A window the user opened comes to the front and takes the keyboard, with or without a Dock icon.
    func bringToFront() {
        // cooperative activation, a plain activate() from the nonactivating panel is declined while another app is active
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            NSRunningApplication.current.activate(from: front)
        } else {
            NSApp.activate()
        }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    /// The Dock icon follows only the setting, open windows do not change it.
    static func activationPolicy(showInDock: Bool) -> NSApplication.ActivationPolicy {
        showInDock ? .regular : .accessory
    }

    static var showInDock = false

    static func updateActivationPolicy() {
        NSApp.setActivationPolicy(activationPolicy(showInDock: showInDock))
    }
}
