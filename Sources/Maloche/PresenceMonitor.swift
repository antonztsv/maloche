import AppKit
import MalocheCore

struct SystemIdleSource: IdleSource {
    var secondsSinceLastInput: TimeInterval {
        // kCGAnyInputEventType, reading it needs no Input Monitoring permission
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// Feeds the tracker: a tick every 5 seconds, away on lock and sleep, an immediate tick on return.
@MainActor
final class PresenceMonitor {
    private let model: AppModel
    private let idleSource: IdleSource
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(model: AppModel, idleSource: IdleSource = SystemIdleSource()) {
        self.model = model
        self.idleSource = idleSource
    }

    func start() {
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // common modes keep ticking while a menu is open
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let names: [(NotificationCenter, Notification.Name, away: Bool)] = [
            (workspace, NSWorkspace.willSleepNotification, true),
            (workspace, NSWorkspace.didWakeNotification, false),
            (workspace, NSWorkspace.screensDidSleepNotification, true),
            (workspace, NSWorkspace.screensDidWakeNotification, false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), false),
        ]
        for (center, name, away) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let name = note.name.rawValue
                MainActor.assumeIsolated {
                    appLog.notice("presence: \(name, privacy: .public)")
                    if away { self?.away() } else { self?.tick() }
                }
            }
            observers.append((center, token))
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    private func tick() {
        model.send(.tick(idleSeconds: idleSource.secondsSinceLastInput))
    }

    private func away() {
        model.send(.systemAway(since: model.now - idleSource.secondsSinceLastInput))
    }
}
