import AppKit
import MalocheCore
import SwiftUI

final class CheckInPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Holds the content in the system glass.
    let glass = NSGlassEffectView()

    init(cornerRadius: CGFloat = 16) {
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
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        // a rounded mask under the glass, so the window shape and its shadow have no square corners
        let shape = NSView()
        shape.wantsLayer = true
        shape.layer?.cornerRadius = cornerRadius
        shape.layer?.cornerCurve = .continuous
        shape.layer?.masksToBounds = true
        contentView = shape
        glass.frame = shape.bounds
        glass.autoresizingMask = [.width, .height]
        shape.addSubview(glass)
    }

    override var canBecomeKey: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        reshapeShadow()
    }

    override func becomeKey() {
        super.becomeKey()
        reshapeShadow()
    }

    override func resignKey() {
        super.resignKey()
        reshapeShadow()
    }

    /// The shadow of a borderless window keeps the shape it was computed from, a stale one shows square edges.
    private func reshapeShadow() {
        // after the next display pass, so the shadow follows the content as drawn
        DispatchQueue.main.async { [weak self] in self?.invalidateShadow() }
    }

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
            // one branch per kind, so another kind of prompt starts with a fresh field
            switch model.panel {
            case .checkIn(let checkIn): CheckInView(model: model, content: .checkIn(checkIn))
            case .awayReturn(let span, let prefill):
                CheckInView(model: model, content: .awayReturn(span: span, prefill: prefill))
            case .breakReturn(let span, let prefill):
                CheckInView(model: model, content: .breakReturn(span: span, prefill: prefill))
            case .dashboard(let day): dashboard(day).keyCommand(.escape, modifiers: [], action: model.close)
            case nil: EmptyView()
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { _ in
            onResize()
        }
    }

    private func dashboard(_ day: DashboardDay) -> DashboardView {
        let catalog = model.catalog
        var data = DashboardData(
            period: day.period, blocks: day.blocks, activities: catalog.activities, projects: catalog.projects,
            customers: catalog.customers, schedule: model.schedule, current: model.nowRow,
            now: model.now, calendar: model.calendar, rounding: model.settings.rounding)
        let overview = ActivityOverview(catalog: catalog, thisMonth: [])
        data.manageable = Set(day.blocks.map(\.activityId)).filter { overview.filter(showing: $0) != nil }
        return DashboardView(
            data: data, moreActions: MoreActionsMenu(model: model), onShowPeriod: model.showDashboard,
            onCheckIn: model.checkIn, onKeepTracking: model.keepTracking,
            onSelect: { model.openManageActivities(selecting: $0) })
    }
}

@MainActor
final class CheckInPanelController: PanelPresenter {
    weak var statusItem: NSStatusItem? {
        didSet {
            highlight = StatusItemHighlight(button: statusItem?.button) { [weak self] in self?.isVisible ?? false }
        }
    }
    private var highlight: StatusItemHighlight?
    var onShowSettings: (() -> Void)?
    var onShowManageActivities: ((Int64?) -> Void)?
    let panel = CheckInPanel()
    private let model: AppModel
    private var hosting: NSView?
    private var activationObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        panel.onCancel = { [weak model] in model?.close() }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak model] _ in
            // a click outside closes the dashboard
            MainActor.assumeIsolated { model?.panelLostFocus() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.position()
                appLog.debug(
                    "panel followed active app to screen \(self.panel.screen?.localizedName ?? "?", privacy: .public)")
            }
        }
    }

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }

    func show(focus: Bool) {
        // a fresh hosting view per opening resets the field and its focus
        let view = NSHostingView(
            rootView: PanelView(
                model: model,
                onResize: { [weak self] in
                    DispatchQueue.main.async { self?.contentResized() }
                }))
        panel.glass.contentView = view
        hosting = view
        position()
        if focus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        highlightStatusItem()
        logState("show focus=\(focus)")
    }

    func update() {
        position()
        panel.orderFrontRegardless()
        highlightStatusItem()
        logState("update")
    }

    func focus() {
        position()
        panel.makeKeyAndOrderFront(nil)
        highlightStatusItem()
        logState("focus")
    }

    func hide() {
        panel.orderOut(nil)
        highlightStatusItem()
    }

    func signalFailure() {
        NSSound.beep()
    }

    func showSettings() {
        onShowSettings?()
    }

    func showManageActivities(selecting activityId: Int64?) {
        onShowManageActivities?(activityId)
    }

    private func highlightStatusItem() {
        highlight?.apply()
    }

    private func contentResized() {
        if panel.isVisible { position() }
    }

    private func logState(_ action: String) {
        #if DEBUG
            logPanel(action)
        #endif
    }

    private func logPanel(_ action: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [panel] in
            let editor = panel.firstResponder as? NSTextView
            appLog.info(
                """
                panel \(action, privacy: .public): visible=\(panel.isVisible) \
                key=\(panel.isKeyWindow) screen=\(panel.screen?.localizedName ?? "?", privacy: .public) \
                frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .private) \
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
