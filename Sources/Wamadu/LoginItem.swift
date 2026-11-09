import ServiceManagement

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
    }

    #if DEBUG
        /// Spike: `open "wamadu Dev.app" --args -SpikeLoginItem register|unregister|status`.
        static func runSpike(_ action: String) {
            do {
                if action == "register" { try setEnabled(true) }
                if action == "unregister" { try setEnabled(false) }
                spikeLog.notice(
                    "login item \(action, privacy: .public): status \(describe(SMAppService.mainApp.status), privacy: .public)"
                )
            } catch {
                spikeLog.error(
                    "login item \(action, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }

        private static func describe(_ status: SMAppService.Status) -> String {
            switch status {
            case .notRegistered: "notRegistered"
            case .enabled: "enabled"
            case .requiresApproval: "requiresApproval"
            case .notFound: "notFound"
            @unknown default: "unknown \(status.rawValue)"
            }
        }
    #endif
}
