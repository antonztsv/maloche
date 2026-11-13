import AppKit

/// The status item button is highlighted while the panel shows, like a menu bar extra with its menu open.
@MainActor
final class StatusItemHighlight {
    private weak var button: NSButton?
    private let isPanelVisible: () -> Bool
    private var observer: NSObjectProtocol?
    var enabled = true

    init(button: NSButton?, center: NotificationCenter = .default, isPanelVisible: @escaping () -> Bool) {
        self.button = button
        self.isPanelVisible = isPanelVisible
        // posted after each event, so a reset by the button's own click tracking lasts until mouse up only
        observer = center.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    func apply() {
        guard enabled, let button else { return }
        let highlighted = isPanelVisible()
        if button.isHighlighted != highlighted { button.highlight(highlighted) }
    }
}
