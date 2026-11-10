import AppKit
import OSLog
import WamaduCore

let appLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "wamadu", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var model: AppModel?
    private var panelController: CheckInPanelController?
    private var presence: PresenceMonitor?
    private var shortcuts: GlobalShortcuts?
    private var settingsWindow: SettingsWindowController?
    private var manageWindow: ManageActivitiesWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var iconMode: TrackerMode?

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
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
        controller.statusItem = item
        self.model = model
        panelController = controller
        showMode()

        model.send(.appLaunched)
        presence = PresenceMonitor(model: model)
        presence?.start()

        let shortcuts = GlobalShortcuts { [weak model] in model?.shortcut($0) }
        self.shortcuts = shortcuts
        registerShortcuts()
        let settingsWindow = SettingsWindowController(model: model) { [weak shortcuts] in shortcuts?.isPaused = $0 }
        controller.onShowSettings = { settingsWindow.show() }
        self.settingsWindow = settingsWindow
        let manageWindow = ManageActivitiesWindowController(model: model)
        controller.onShowManageActivities = { manageWindow.show() }
        self.manageWindow = manageWindow

        // launches with debug arguments are for manual testing and skip the welcome
        if model.welcomeDue && !CommandLine.arguments.contains(where: { $0.hasPrefix("-Debug") }) {
            let welcomeWindow = WelcomeWindowController(model: model)
            self.welcomeWindow = welcomeWindow
            welcomeWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveState()
    }

    /// The hotkeys follow the settings.
    private func registerShortcuts() {
        guard let model, let shortcuts else { return }
        let wanted = withObservationTracking {
            model.settings.shortcuts
        } onChange: {
            Task { @MainActor in self.registerShortcuts() }
        }
        let failed = shortcuts.register(wanted)
        if !failed.isEmpty {
            appLog.error(
                "shortcuts not registered: \(failed.map(\.rawValue).sorted().joined(separator: ", "), privacy: .public)"
            )
        }
    }

    /// The menu bar icon follows the tracker mode.
    private func showMode() {
        guard let model else { return }
        let mode = withObservationTracking {
            model.mode
        } onChange: {
            Task { @MainActor in self.showMode() }
        }
        guard mode != iconMode else { return }
        iconMode = mode
        statusItem?.button?.image = MenuBarIcon.image(for: mode)
    }

    @objc private func statusItemClicked() {
        model?.statusItemClicked()
    }

    private static func makeModel() throws -> AppModel {
        let url = try AppDatabase.defaultURL(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.antonztsv.wamadu.dev")
        return try AppModel(
            database: .open(at: url), stateURL: url.deletingLastPathComponent().appending(path: "tracker-state.json"),
            settingsStore: UserDefaults.standard,
            backups: url.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory),
            adjustTracker: { settings in
                #if DEBUG
                    // manual testing, e.g. `open "wamadu Dev.app" --args -DebugCheckInInterval 60 -DebugIdleThreshold 120`
                    let defaults = UserDefaults.standard
                    if defaults.double(forKey: "DebugCheckInInterval") > 0 {
                        settings.checkInInterval = defaults.double(forKey: "DebugCheckInInterval")
                    }
                    if defaults.double(forKey: "DebugIdleThreshold") > 0 {
                        settings.awayThreshold = defaults.double(forKey: "DebugIdleThreshold")
                    }
                #endif
            })
    }
}
