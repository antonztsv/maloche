import AppKit
import MalocheCore

/// Keeps the app's windows in front when the system deactivates it, they would fall behind the app owning the menu bar.
@MainActor
enum ActivationKeeper {
    private static var resignedAt: Date?
    private static var policyChangedAt: Date?
    private static var windows: [NSWindow] = []
    private static var key: NSWindow?
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    windows = NSApp.orderedWindows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
                    key = NSApp.keyWindow.flatMap { windows.contains($0) ? $0 : nil }
                }
            })
        observers.append(
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    resignedAt = .now
                    // the system hands activation away a second time about 120 ms after the switch
                    guard SystemDeactivation.caused(by: policyChangedAt, resignedAt: resignedAt) else { return }
                    logActivation("keeper: policy change deactivated the app, reactivating")
                    restore(activating: true)
                }
            })
    }

    /// Before switching to accessory while active, the switch hands activation to another app.
    static func policyWillChange(to policy: NSApplication.ActivationPolicy) {
        guard NSApp.isActive, policy == .accessory, NSApp.activationPolicy() != .accessory else { return }
        policyChangedAt = .now
    }

    /// The click on the status item deactivated the app, its windows come back above the other app without taking focus.
    static func statusItemClicked() {
        guard SystemDeactivation.caused(by: .now, resignedAt: resignedAt) else { return }
        resignedAt = nil
        logActivation("keeper: status item click deactivated the app, reordering windows")
        restore(activating: false)
    }

    private static func restore(activating: Bool) {
        for window in windows.reversed() where window.isVisible { window.orderFrontRegardless() }
        if activating, let key, key.isVisible { key.bringToFront() }
    }
}
