import AppKit

extension NSWindow {
    /// A window the user opened comes to the front and takes the keyboard, with or without a Dock icon.
    func bringToFront() {
        logActivation("bringToFront begin \(identifier?.rawValue ?? "?")")
        // without a Dock icon a plain activate() is often declined
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        logActivation("bringToFront end \(identifier?.rawValue ?? "?")")
    }

    /// The Dock icon follows only the setting, open windows do not change it.
    static func activationPolicy(showInDock: Bool) -> NSApplication.ActivationPolicy {
        showInDock ? .regular : .accessory
    }

    static var showInDock = false

    static func updateActivationPolicy() {
        logActivation("setActivationPolicy begin showInDock=\(showInDock)")
        let policy = activationPolicy(showInDock: showInDock)
        // switching to accessory hands activation to another app, the window the switch was made in stays key
        let hides = NSApp.isActive && policy == .accessory && NSApp.activationPolicy() != .accessory
        let key = hides ? NSApp.keyWindow : nil
        NSApp.setActivationPolicy(policy)
        if let key {
            NSApp.activate(ignoringOtherApps: true)
            key.makeKeyAndOrderFront(nil)
        }
        logActivation("setActivationPolicy end")
    }
}
