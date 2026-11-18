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

    private var resizeTimer: Timer?

    /// Steps the frame on SwiftUI's ease in out curve with plain frame changes, so the content is laid out for every
    /// step. A zero duration resizes at once.
    func setFrame(_ frame: NSRect, duration: TimeInterval) {
        resizeTimer?.invalidate()
        guard duration > 0 else { return setFrame(frame, display: true) }
        let from = self.frame
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] timer in
            let progress = min((CACurrentMediaTime() - start) / duration, 1)
            if progress == 1 { timer.invalidate() }
            MainActor.assumeIsolated { self?.step(from: from, to: frame, progress: progress) }
        }
        RunLoop.main.add(timer, forMode: .common)
        resizeTimer = timer
    }

    private func step(from: NSRect, to frame: NSRect, progress: Double) {
        guard progress < 1 else { return setFrame(frame, display: true) }
        let t = UnitCurve.easeInOut.value(at: progress)
        // a whole point height under a fixed top, so rounding never nudges the top edge
        let height = (from.height + (frame.height - from.height) * t).rounded()
        let top = from.maxY + (frame.maxY - from.maxY) * t
        let x = from.minX + (frame.minX - from.minX) * t
        let width = from.width + (frame.width - from.width) * t
        setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
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
            case .dashboard(let day):
                // today's timeline grows with the clock, which views do not observe
                TimelineView(.everyMinute) { _ in dashboard(day) }
                    .keyCommand(.escape, modifiers: [], action: model.close)
            case nil: EmptyView()
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { _ in
            onResize()
        }
        // top aligned while the panel follows a new height, without minHeight a taller content is centered instead
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    private func dashboard(_ day: DashboardDay) -> DashboardView {
        let catalog = model.catalog
        var data = DashboardData(
            period: day.period, blocks: day.blocks, activities: catalog.activities, projects: catalog.projects,
            customers: catalog.customers, current: model.nowRow,
            now: model.now, calendar: model.calendar, rounding: model.settings.rounding)
        data.manageable = Set(day.blocks.map(\.activityId)).filter { catalog.activity($0)?.kind == .regular }
        return DashboardView(
            data: data, moreActions: MoreActionsMenu(model: model), onShowPeriod: model.showDashboard,
            onCheckIn: model.checkIn, onKeepTracking: model.keepTracking,
            onSelect: { model.openManageActivities(selecting: $0) })
    }
}

@MainActor
final class CheckInPanelController: PanelPresenter {
    weak var statusItem: NSStatusItem?
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
            MainActor.assumeIsolated {
                model?.panelLostFocus()
            }
        }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // the icon click reaches the model before the button, so the session or action cannot reopen the panel
        _ = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self,
                Self.isIconClick(
                    in: event.window, button: self.statusItem?.button?.window, panelVisible: self.isVisible)
            else { return event }
            self.model.statusItemClicked()
            return nil
        }
        // clicks in other apps, the menu bar and other status items, mouse events need no permission
        _ = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak model] _ in
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

    /// Only the controller sizes the panel, with the content's fitting size; the default options let AppKit resize
    /// it at once while SwiftUI still animates, which made a fold jump before it moved.
    static func hostingView<Content: View>(_ rootView: Content) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: rootView)
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }

    func show(focus: Bool) {
        // a fresh hosting view per opening resets the field and its focus
        let view = Self.hostingView(
            PanelView(
                model: model,
                onResize: { [weak self] in
                    DispatchQueue.main.async { self?.contentResized() }
                }))
        panel.glass.contentView = view
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
        if #available(macOS 27, *) { statusItem?.expandedInterfaceSession?.cancel() }
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

    /// A click on the icon while the panel shows goes to the model, so it closes or focuses the panel.
    static func isIconClick(in window: NSWindow?, button: NSWindow?, panelVisible: Bool) -> Bool {
        panelVisible && window != nil && window === button
    }

    private func contentResized() {
        guard panel.isVisible else { return }
        guard case .dashboard = model.panel, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return position()
        }
        position(duration: DashboardList.foldDuration)
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

    private func position(duration: TimeInterval = 0) {
        let size = hosting?.fittingSize ?? panel.frame.size
        guard size.height > 0, let screen = NSScreen.active else { return }
        var anchorOffset: CGFloat = 200
        if let button = statusItem?.button, let window = button.window, let buttonScreen = window.screen {
            anchorOffset = buttonScreen.frame.maxX - window.frame.midX
        }
        let frame = PanelPlacement.panelFrame(
            size: size, anchorOffsetFromRight: anchorOffset, screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame, margin: 6)
        panel.setFrame(frame, duration: duration)
    }
}
