import AppKit

extension NSWindow {
    /// A window the user opened comes to the front and becomes key.
    func bringToFront() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}
