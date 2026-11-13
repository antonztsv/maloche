#if DEBUG
    import AppKit
    import MalocheCore

    /// One thing switched off (or tried) per run, e.g. `open "maloche Dev.app" --args -DebugHighlightSuspect noKeyPanel`.
    enum HighlightSuspect: String {
        case none, noIconUpdates, noKeyPanel, noObserver, expandedSession
    }

    @MainActor
    enum HighlightDiagnosis {
        static let suspect = UserDefaults.standard.string(forKey: "DebugHighlightSuspect").flatMap(
            HighlightSuspect.init(rawValue:))

        static var caption: String? { suspect.map { "highlight suspect: \($0.rawValue)" } }

        static func logAfterOpening(item: NSStatusItem?, panel: NSWindow) {
            guard let suspect else { return }
            for delay in [0.2, 1, 3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak item, weak panel] in
                    let button = item?.button
                    var session = "n/a"
                    if #available(macOS 27, *) { session = item?.expandedInterfaceSession == nil ? "nil" : "active" }
                    appLog.notice(
                        """
                        highlight \(suspect.rawValue, privacy: .public) +\(delay, privacy: .public)s \
                        isHighlighted=\(button?.isHighlighted ?? false, privacy: .public) \
                        state=\(button?.state.rawValue ?? -1, privacy: .public) \
                        panelVisible=\(panel?.isVisible ?? false, privacy: .public) \
                        panelKey=\(panel?.isKeyWindow ?? false, privacy: .public) \
                        appActive=\(NSApp.isActive, privacy: .public) session=\(session, privacy: .public)
                        """)
                }
            }
        }
    }

    /// The macOS 27 expanded interface session, the menu bar draws the pill while it lasts.
    @available(macOS 27, *)
    @MainActor
    final class ExpandedSessionDiagnosis: NSObject, @MainActor NSStatusItemExpandedInterfaceDelegate {
        private let model: AppModel
        private let isPanelVisible: () -> Bool

        init(model: AppModel, isPanelVisible: @escaping () -> Bool) {
            self.model = model
            self.isPanelVisible = isPanelVisible
        }

        func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
            appLog.notice("highlight expandedSession began")
            model.statusItemClicked()
        }

        func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
            appLog.notice("highlight expandedSession ended")
            if isPanelVisible() { model.close() }
        }
    }
#endif
