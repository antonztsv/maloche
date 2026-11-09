import AppKit
import OSLog

let spikeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "wamadu", category: "spike")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let panelController = CheckInPanelController()
    private var spikeTimer: Timer?
    private var presence: PresenceMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "wamadu")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        panelController.statusItem = item

        // Spike only: open the panel periodically, e.g. `open "wamadu Dev.app" --args -SpikeCheckInInterval 30`.
        let idleThreshold = UserDefaults.standard.double(forKey: "SpikeIdleThreshold")
        presence = PresenceMonitor(threshold: idleThreshold > 0 ? idleThreshold : 120)
        presence?.start()

        #if DEBUG
            if UserDefaults.standard.bool(forKey: "SpikeSelfTest") {
                Task { await panelController.runSelfTest() }
            }
        #endif
        let interval = UserDefaults.standard.double(forKey: "SpikeCheckInInterval")
        if interval > 0 {
            spikeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                MainActor.assumeIsolated { self.panelController.show(reason: "timer") }
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(
                withTitle: String(localized: "Quit wamadu"), action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
            return
        }
        panelController.toggle()
    }
}
