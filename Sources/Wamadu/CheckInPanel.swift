import AppKit
import SwiftUI
import WamaduCore

final class CheckInPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { orderOut(nil) }
    }
}

/// What the panel shows, its height follows the content.
struct PanelView: View {
    let model: AppModel
    let onResize: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch model.panel {
            case .checkIn(let checkIn): CheckInView(model: model, checkIn: checkIn)
            case nil: EmptyView()
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { _ in
            onResize()
        }
    }
}

@MainActor
final class CheckInPanelController: PanelPresenter {
    weak var statusItem: NSStatusItem?
    let panel = CheckInPanel()
    private let model: AppModel
    private let glass = NSGlassEffectView()
    private var hosting: NSView?
    private var activationObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        glass.style = .regular
        glass.cornerRadius = 16
        panel.contentView = glass
        panel.onCancel = { [weak model] in model?.close() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.position()
                spikeLog.debug(
                    "panel followed active app to screen \(self.panel.screen?.localizedName ?? "?", privacy: .public)")
            }
        }
    }

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }

    func show(focus: Bool) {
        // a fresh hosting view per opening resets the field and its focus
        let view = NSHostingView(
            rootView: PanelView(model: model) { [weak self] in
                DispatchQueue.main.async { self?.contentResized() }
            })
        glass.contentView = view
        hosting = view
        position()
        if focus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        logState("show focus=\(focus)")
    }

    func update() {
        position()
        panel.orderFrontRegardless()
        logState("update")
    }

    func focus() {
        position()
        panel.makeKeyAndOrderFront(nil)
        logState("focus")
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func contentResized() {
        if panel.isVisible { position() }
    }

    private func logState(_ action: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [panel] in
            let editor = panel.firstResponder as? NSTextView
            spikeLog.info(
                """
                panel \(action, privacy: .public): visible=\(panel.isVisible) \
                key=\(panel.isKeyWindow) screen=\(panel.screen?.localizedName ?? "?", privacy: .public) \
                frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public) \
                fieldEditor=\(editor != nil) selection=\(editor.map { NSStringFromRange($0.selectedRange()) } ?? "-", privacy: .public)
                """)
        }
    }

    private func position() {
        let size = hosting?.fittingSize ?? panel.frame.size
        guard size.height > 0,
            let screen = Self.screenWithFrontmostWindow() ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        var anchorOffset: CGFloat = 200
        if let button = statusItem?.button, let window = button.window, let buttonScreen = window.screen {
            anchorOffset = buttonScreen.frame.maxX - window.frame.midX
        }
        let frame = PanelPlacement.panelFrame(
            size: size, anchorOffsetFromRight: anchorOffset, screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame, margin: 6)
        panel.setFrame(frame, display: true)
    }

    /// Window bounds and owner are readable without the screen recording permission, titles are not needed.
    private static func screenWithFrontmostWindow() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let info = list.first(where: {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
            }),
            let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            let primaryHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        let window = PanelPlacement.cocoaRect(fromWindowListRect: bounds, primaryScreenHeight: primaryHeight)
        let screens = NSScreen.screens
        return PanelPlacement.screenIndex(containing: window, screens: screens.map(\.frame)).map { screens[$0] }
    }
}
