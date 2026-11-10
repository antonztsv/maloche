import AppKit
import OSLog
import WamaduCore

let spikeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "wamadu", category: "spike")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var model: AppModel?
    private var panelController: CheckInPanelController?
    private var presence: PresenceMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            if let directory = Screenshots.outputDirectory {
                do {
                    try Screenshots.renderAll(to: directory)
                } catch {
                    FileHandle.standardError.write(Data("screenshots failed: \(error)\n".utf8))
                    exit(1)
                }
                NSApp.terminate(nil)
                return
            }
        #endif
        let model: AppModel
        do {
            model = try Self.makeModel()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }
        let controller = CheckInPanelController(model: model)
        model.presenter = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "wamadu")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        controller.statusItem = item
        self.model = model
        panelController = controller

        model.send(.appLaunched)
        presence = PresenceMonitor(model: model)
        presence?.start()

        #if DEBUG
            if let action = UserDefaults.standard.string(forKey: "SpikeLoginItem") {
                LoginItem.runSpike(action)
            }
            if UserDefaults.standard.bool(forKey: "SpikeSelfTest") {
                Task { await SpikeSelfTest.run(model: model, controller: controller) }
            }
        #endif
    }

    private static func makeModel() throws -> AppModel {
        let url = try AppDatabase.defaultURL(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.antonztsv.wamadu.dev")
        var settings = TrackerSettings()
        #if DEBUG
            // manual testing, e.g. `open "wamadu Dev.app" --args -SpikeCheckInInterval 60 -SpikeIdleThreshold 120`
            let defaults = UserDefaults.standard
            if defaults.double(forKey: "SpikeCheckInInterval") > 0 {
                settings.checkInInterval = defaults.double(forKey: "SpikeCheckInInterval")
            }
            if defaults.double(forKey: "SpikeIdleThreshold") > 0 {
                settings.awayThreshold = defaults.double(forKey: "SpikeIdleThreshold")
            }
        #endif
        return try AppModel(
            database: .open(at: url), stateURL: url.deletingLastPathComponent().appending(path: "tracker-state.json"),
            settings: settings)
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
        model?.statusItemClicked()
    }
}
