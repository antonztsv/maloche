#if DEBUG
    import AppKit

    /// Dev builds log every activation, key and main window change with a snapshot of the app's windows.
    @MainActor
    enum ActivationLog {
        private static var observers: [NSObjectProtocol] = []

        static func start() {
            let app: [Notification.Name] = [
                NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            ]
            let window: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
            ]
            let workspace: [Notification.Name] = [
                NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
            ]
            for name in app + window {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                        let event = short(note.name)
                        nonisolated(unsafe) let window = note.object as? NSWindow
                        MainActor.assumeIsolated { log("\(event) \(window.map(describe) ?? "")") }
                    })
            }
            for name in workspace {
                observers.append(
                    NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                        note in
                        let event = short(note.name)
                        let other = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                            .bundleIdentifier
                        MainActor.assumeIsolated { log("\(event) \(other ?? "?")") }
                    })
            }
            log("start")
        }

        /// One line: the event, then active state, policy, key, main and the visible windows front to back.
        static func log(_ event: String) {
            let policy =
                switch NSApp.activationPolicy() {
                case .regular: "regular"
                case .accessory: "accessory"
                default: "prohibited"
                }
            let ordered = NSApp.orderedWindows.filter(\.isVisible).map(describe).joined(separator: ", ")
            appLog.notice(
                """
                act \(event, privacy: .public) | active=\(NSApp.isActive) policy=\(policy, privacy: .public) \
                front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public) \
                key=\(NSApp.keyWindow.map(describe) ?? "-", privacy: .public) \
                main=\(NSApp.mainWindow.map(describe) ?? "-", privacy: .public) \
                windows=[\(ordered, privacy: .public)]
                """)
        }

        private static func describe(_ window: NSWindow) -> String {
            let name = window.identifier?.rawValue ?? String(describing: type(of: window))
            return "\(name)#\(window.windowNumber)\(window.isVisible ? "" : "(hidden)")"
        }

        nonisolated private static func short(_ name: Notification.Name) -> String {
            name.rawValue.replacingOccurrences(of: "Notification", with: "")
                .replacingOccurrences(of: "NSApplication", with: "app.")
                .replacingOccurrences(of: "NSWorkspace", with: "ws.")
                .replacingOccurrences(of: "NSWindow", with: "win.")
        }
    }
#endif

@MainActor
func logActivation(_ event: @autoclosure () -> String) {
    #if DEBUG
        ActivationLog.log(event())
    #endif
}
