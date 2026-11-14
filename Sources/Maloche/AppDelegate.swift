import AppKit
import MalocheCore
import OSLog

let appLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "maloche", category: "app")

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
    private var resignObserver: NSObjectProtocol?
    private var session: AnyObject?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        appLog.notice(
            "launched \(info["CFBundleShortVersionString"] as? String ?? "?", privacy: .public) build \(info["CFBundleVersion"] as? String ?? "?", privacy: .public) from \(Bundle.main.bundlePath, privacy: .private)"
        )
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
        if #available(macOS 27, *) {
            let session = StatusItemSession(model: model, controller: controller)
            item.expandedInterfaceDelegate = session
            self.session = session
        } else {
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
        }
        statusItem = item
        controller.statusItem = item
        self.model = model
        panelController = controller
        showMode()
        showInDock()
        #if DEBUG
            ActivationLog.start()
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { _ in
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
                appLog.debug("app resigned active, frontmost \(front, privacy: .private)")
            }
        #endif

        model.send(.appLaunched)
        presence = PresenceMonitor(model: model)
        presence?.start()

        let shortcuts = GlobalShortcuts { [weak model] in model?.shortcut($0) }
        self.shortcuts = shortcuts
        registerShortcuts()
        let updater = Updater(model: model)
        self.updater = updater
        let settingsWindow = SettingsWindowController(model: model, checkForUpdates: updater.map { $0.checkNow }) {
            [weak shortcuts] in shortcuts?.isPaused = $0
        }
        controller.onShowSettings = { settingsWindow.show() }
        self.settingsWindow = settingsWindow
        let manageWindow = ManageActivitiesWindowController(model: model)
        controller.onShowManageActivities = { manageWindow.show(selecting: $0) }
        self.manageWindow = manageWindow

        var skipsWelcome = false
        #if DEBUG
            skipsWelcome = CommandLine.arguments.contains { $0.hasPrefix("-Debug") }
        #endif
        if model.welcomeDue && !skipsWelcome {
            let welcomeWindow = WelcomeWindowController(model: model, showsUpdates: updater != nil)
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

    /// The Dock icon follows the setting.
    private func showInDock() {
        guard let model else { return }
        NSWindow.showInDock = withObservationTracking {
            model.settings.showInDock
        } onChange: {
            Task { @MainActor in self.showInDock() }
        }
        NSWindow.updateActivationPolicy()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logActivation("reopen (Dock click) panel=\(model?.panel.kindForLog ?? "-")")
        model?.statusItemClicked()
        return false
    }

    @objc func showSettings() {
        settingsWindow?.show()
    }

    @objc private func statusItemClicked() {
        model?.statusItemClicked()
    }

    private static func makeModel() throws -> AppModel {
        let url = try AppDatabase.defaultURL(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.antonztsv.maloche.dev")
        return try AppModel(
            database: .open(at: url), stateURL: url.deletingLastPathComponent().appending(path: "tracker-state.json"),
            settingsStore: UserDefaults.standard,
            backups: url.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory),
            adjustTracker: { settings in
                #if DEBUG
                    // manual testing, e.g. `open "maloche Dev.app" --args -DebugCheckInInterval 60 -DebugIdleThreshold 120`
                    let defaults = UserDefaults.standard
                    if defaults.double(forKey: "DebugCheckInInterval") > 0 {
                        settings.checkInInterval = defaults.double(forKey: "DebugCheckInInterval")
                    }
                    if defaults.double(forKey: "DebugIdleThreshold") > 0 {
                        settings.awayThreshold = defaults.double(forKey: "DebugIdleThreshold")
                    }
                #endif
            }, builtInNames: AppModel.localizedBuiltInNames)
    }
}

/// On macOS 27 the panel opened by the icon is an expanded interface session, the menu bar shows the pill while it lasts.
@available(macOS 27, *)
@MainActor
final class StatusItemSession: NSObject, @MainActor NSStatusItemExpandedInterfaceDelegate {
    private let model: AppModel
    private weak var controller: CheckInPanelController?

    init(model: AppModel, controller: CheckInPanelController) {
        self.model = model
        self.controller = controller
    }

    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        logActivation("session didBegin panel=\(model.panel.kindForLog) visible=\(controller?.isVisible == true)")
        model.statusItemClicked()
        logActivation("session after click panel=\(model.panel.kindForLog) visible=\(controller?.isVisible == true)")
        if controller?.isVisible != true { session.cancel() }
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        logActivation("session didEnd panel=\(model.panel.kindForLog)")
        model.panelLostFocus()
    }
}

extension Optional where Wrapped == PanelContent {
    /// The kind of panel content without names, for the log.
    var kindForLog: String {
        switch self {
        case .checkIn(let checkIn): "checkIn.\(checkIn.mode)"
        case .awayReturn: "awayReturn"
        case .breakReturn: "breakReturn"
        case .dashboard: "dashboard"
        case nil: "none"
        }
    }
}

extension AppModel {
    /// Break and Private in the language of the app.
    static var localizedBuiltInNames: [ActivityKind: String] {
        [.break: String(localized: "Break"), .private: String(localized: "Private")]
    }
}
