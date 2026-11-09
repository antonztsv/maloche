import AppKit
import SwiftUI
import WamaduCore

final class CheckInPanel: NSPanel {
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
        orderOut(nil)
    }
}

@MainActor
final class CheckInPanelController {
    weak var statusItem: NSStatusItem?
    private let panel = CheckInPanel()
    private let glass = NSGlassEffectView()
    private var hosting: NSView?
    private var activationObserver: NSObjectProtocol?

    init() {
        glass.style = .regular
        glass.cornerRadius = 16
        panel.contentView = glass
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

    #if DEBUG
        func runSelfTest() async { await SpikeSelfTest.run(self, panel: panel) }
    #endif

    func toggle() {
        panel.isVisible ? panel.orderOut(nil) : show(reason: "status item")
    }

    func show(reason: String) {
        // a fresh hosting view per check-in resets the field and its focus
        let view = NSHostingView(
            rootView: CheckInView(onLog: { [weak self] text in
                spikeLog.info("logged \(text, privacy: .public)")
                self?.panel.orderOut(nil)
            }))
        glass.contentView = view
        hosting = view
        position()
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [panel] in
            let editor = panel.firstResponder as? NSTextView
            spikeLog.info(
                """
                panel shown (\(reason, privacy: .public)): key=\(panel.isKeyWindow) \
                visible=\(panel.isOnActiveSpace) screen=\(panel.screen?.localizedName ?? "?", privacy: .public) \
                frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public) \
                fieldEditor=\(editor != nil) selection=\(editor.map { NSStringFromRange($0.selectedRange()) } ?? "-", privacy: .public)
                """)
        }
    }

    private func position() {
        let size = hosting?.fittingSize ?? panel.frame.size
        let screen = Self.screenWithFrontmostWindow() ?? NSScreen.main ?? NSScreen.screens[0]
        var anchorOffset: CGFloat = 200
        if let button = statusItem?.button, let window = button.window, let buttonScreen = window.screen {
            anchorOffset = buttonScreen.frame.maxX - window.frame.midX
        }
        let frame = PanelPlacement.panelFrame(
            size: size, anchorOffsetFromRight: anchorOffset, visibleFrame: screen.visibleFrame, margin: 6)
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
