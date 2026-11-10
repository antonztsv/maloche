import AppKit
import SwiftUI
import WamaduCore

/// The settings window, one tab per pane in the toolbar; opening it again brings the same window to the front.
@MainActor
final class SettingsWindowController {
    static let identifier = NSUserInterfaceItemIdentifier("settings")
    /// The panes are this wide, the height follows the selected pane.
    static let width: CGFloat = 640

    private let model: AppModel
    private let onRecording: (Bool) -> Void
    private(set) lazy var window = makeWindow()

    /// `onRecording` pauses the global hotkeys while a shortcut field records.
    init(model: AppModel, onRecording: @escaping (Bool) -> Void) {
        self.model = model
        self.onRecording = onRecording
    }

    /// From Settings… in the more menu only; a normal window needs the app active.
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        let panes: [(String, String, AnyView)] = [
            (
                String(localized: "General"), "gearshape",
                AnyView(GeneralSettingsView(model: model, onRecording: onRecording))
            ),
            (String(localized: "Schedule"), "calendar", AnyView(ScheduleSettingsView(model: model))),
            (String(localized: "Rounding"), "clock", AnyView(RoundingSettingsView(model: model))),
            (String(localized: "Backup"), "archivebox", AnyView(BackupSettingsView(model: model))),
        ]
        for (label, symbol, view) in panes {
            let hosting = NSHostingController(rootView: view)
            hosting.title = label
            let item = NSTabViewItem(viewController: hosting)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.identifier = Self.identifier
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        tabs.fit(window)
        window.center()
        return window
    }
}

/// Sizes the window to the selected pane, the top edge stays.
private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        if let window = view.window { fit(window) }
    }

    func fit(_ window: NSWindow) {
        guard selectedTabViewItemIndex >= 0, let pane = tabViewItems[selectedTabViewItemIndex].view,
            let content = window.contentView
        else { return }
        // by the difference to the content, the toolbar may come and go
        var frame = window.frame
        frame.size.width += SettingsWindowController.width - content.frame.width
        let grow = pane.fittingSize.height - content.frame.height
        frame.size.height += grow
        frame.origin.y -= grow
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
