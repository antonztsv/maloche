import AppKit
import WamaduCore

struct SystemIdleSource: IdleSource {
    var secondsSinceLastInput: TimeInterval {
        // kCGAnyInputEventType, reading it needs no Input Monitoring permission
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// Spike: logs idle, sleep and lock events.
@MainActor
final class PresenceMonitor {
    private let idleSource: IdleSource
    private var transitions: IdleTransitions
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(idleSource: IdleSource = SystemIdleSource(), threshold: TimeInterval) {
        self.idleSource = idleSource
        transitions = IdleTransitions(threshold: threshold)
    }

    func start() {
        spikeLog.notice(
            "presence: start, idle now \(Int(self.idleSource.secondsSinceLastInput))s, threshold \(Int(self.transitions.threshold))s"
        )
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
            (distributed, Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                let name = note.name.rawValue
                MainActor.assumeIsolated { spikeLog.notice("presence: \(name, privacy: .public)") }
            }
            observers.append((center, token))
        }
    }

    private func poll() {
        if let event = transitions.update(idleSeconds: idleSource.secondsSinceLastInput, now: Date()) {
            spikeLog.notice("presence: \(String(describing: event), privacy: .public)")
        }
    }
}
