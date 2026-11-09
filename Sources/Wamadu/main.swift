import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "wamadu")
        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Quit wamadu"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
