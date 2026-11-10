import Carbon.HIToolbox
import OSLog
import WamaduCore

/// System-wide hotkeys via Carbon, which need no Accessibility or Input Monitoring permission.
@MainActor
final class GlobalShortcuts {
    private static let signature = "wmdu".utf8.reduce(OSType(0)) { $0 << 8 | OSType($1) }

    private let onAction: (ShortcutAction) -> Void
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    init(onAction: @escaping (ShortcutAction) -> Void) {
        self.onAction = onAction
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, let userData else { return status }
                let shortcuts = Unmanaged<GlobalShortcuts>.fromOpaque(userData).takeUnretainedValue()
                // hotkey events arrive on the main run loop
                MainActor.assumeIsolated { shortcuts.fire(id) }
                return noErr
            }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { appLog.error("installing the hotkey handler failed: \(status)") }
    }

    isolated deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Replaces all registered hotkeys; returns the actions whose combo is invalid or taken by another app.
    @discardableResult
    func register(_ shortcuts: [ShortcutAction: Shortcut]) -> Set<ShortcutAction> {
        unregisterAll()
        var failed = Set<ShortcutAction>()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let shortcut = shortcuts[action] else { continue }
            var ref: EventHotKeyRef?
            let status =
                shortcut.isValid
                ? RegisterEventHotKey(
                    shortcut.keyCode, shortcut.carbonModifiers,
                    EventHotKeyID(signature: Self.signature, id: UInt32(index)),
                    GetApplicationEventTarget(), 0, &ref)
                : OSStatus(paramErr)
            if status == noErr, let ref {
                hotKeys.append(ref)
            } else {
                failed.insert(action)
            }
        }
        return failed
    }

    func unregisterAll() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
    }

    private func fire(_ id: EventHotKeyID) {
        guard id.signature == Self.signature, ShortcutAction.allCases.indices.contains(Int(id.id)) else { return }
        let action = ShortcutAction.allCases[Int(id.id)]
        #if DEBUG
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "wamadu", category: "shortcuts")
                .debug("hotkey \(action.rawValue, privacy: .public)")
        #endif
        onAction(action)
    }
}
