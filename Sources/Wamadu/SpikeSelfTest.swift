#if DEBUG
    import AppKit
    import WamaduCore

    /// Sends key events to the panel in-process, no accessibility permission needed. Writes to the dev database.
    @MainActor
    enum SpikeSelfTest {
        static func run(model: AppModel, controller: CheckInPanelController) async {
            let panel = controller.panel
            func key(_ chars: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: modifiers,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil, characters: chars,
                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
                    if let event { NSApp.sendEvent(event) }
                }
            }
            func pause(_ milliseconds: Int = 400) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
            func selection() -> String {
                (panel.firstResponder as? NSTextView).map { NSStringFromRange($0.selectedRange()) } ?? "-"
            }
            func field() -> String { (panel.firstResponder as? NSTextView)?.string ?? "-" }
            func current() -> String { model.catalog.activity(model.tracker.currentActivity)?.name ?? "-" }
            func blocks() -> Int {
                (try? model.database.blocks(in: DateInterval(start: .distantPast, end: .distantFuture)).count) ?? -1
            }
            let returnKey = ("\r", UInt16(36))
            let downArrow = (String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!), UInt16(125))

            model.apply([
                .showCheckIn(
                    CheckInPrompt(
                        span: DateInterval(start: .now - 900, end: .now), prefill: model.tracker.currentActivity,
                        canSplit: false))
            ])
            await pause()
            spikeLog.info("self-test timer: key=\(panel.isKeyWindow) visible=\(panel.isVisible)")
            model.open(.shortcut)
            await pause()
            spikeLog.info(
                "self-test shortcut focuses: key=\(panel.isKeyWindow) selection=\(selection(), privacy: .public)")
            key("\u{1b}", 53)
            await pause()
            spikeLog.info(
                "self-test escape: visible=\(panel.isVisible) panel=\(model.panel == nil ? "none" : "set", privacy: .public)"
            )

            let stamp = Int(Date().timeIntervalSince1970) % 100_000
            for name in ["Self-test \(stamp) one", "Self-test \(stamp) two"] {
                let activities = model.catalog.activities.count
                model.statusItemClicked()
                await pause()
                key(name, 0)
                spikeLog.info("self-test typed: field=\(field(), privacy: .public)")
                key(returnKey.0, returnKey.1)
                await pause()
                spikeLog.info(
                    """
                    self-test new name and return: visible=\(panel.isVisible) current=\(current(), privacy: .public) \
                    activities \(activities) -> \(model.catalog.activities.count)
                    """)
                await pause(1200)
            }

            var before = blocks()
            model.statusItemClicked()
            await pause()
            spikeLog.info(
                "self-test prefill: field=\(field(), privacy: .public) selection=\(selection(), privacy: .public)")
            key(returnKey.0, returnKey.1)
            await pause()
            spikeLog.info(
                "self-test return logs prefill: current=\(current(), privacy: .public) blocks \(before) -> \(blocks())")

            await pause(1200)
            before = blocks()
            model.statusItemClicked()
            await pause()
            key(downArrow.0, downArrow.1, [.numericPad, .function])
            key(returnKey.0, returnKey.1)
            await pause()
            spikeLog.info(
                "self-test arrow down and return: current=\(current(), privacy: .public) blocks \(before) -> \(blocks())"
            )

            model.statusItemClicked()
            await pause()
            key("x", 7)
            await pause()
            key("a", 0, .command)
            spikeLog.info(
                "self-test cmd-a: field=\(field(), privacy: .public) selection=\(selection(), privacy: .public)")
            key("\u{1b}", 53)
            await pause()

            let probe = MenuProbe()
            func project() -> String {
                let activity = model.catalog.activity(model.tracker.currentActivity)
                let project = model.catalog.project(activity?.projectId)
                return "\(project?.name ?? "-"), \(model.catalog.customer(project?.customerId)?.name ?? "-")"
            }
            func tabToProjectMenu(picking title: String) async {
                probe.pick = title
                let menus = probe.closed
                key("\t", 48)
                for _ in 0..<30 where probe.closed == menus { await pause(100) }
                await pause()
                spikeLog.info("self-test tab opens project menu: items=\(probe.items, privacy: .public)")
            }
            model.statusItemClicked()
            await pause()
            key("Self-test \(stamp) three", 0)
            await pause()
            await tabToProjectMenu(picking: "New project…")
            key("\u{1b}", 53)
            await pause()
            spikeLog.info("self-test escape in project form: field=\(field(), privacy: .public)")
            await tabToProjectMenu(picking: "New project…")
            key("Self-test \(stamp) project", 0)
            key("\t", 48)
            await pause()
            key("Self-test \(stamp) customer", 0)
            spikeLog.info("self-test new project form: field=\(field(), privacy: .public)")
            key(returnKey.0, returnKey.1)
            await pause()
            spikeLog.info("self-test project created: field=\(field(), privacy: .public)")
            key(returnKey.0, returnKey.1)
            await pause()
            spikeLog.info(
                "self-test created with new project: current=\(current(), privacy: .public) \(project(), privacy: .public)"
            )

            model.statusItemClicked()
            await pause()
            key("Self-test \(stamp) four", 0)
            await pause()
            await tabToProjectMenu(picking: "Self-test \(stamp) project")
            key(returnKey.0, returnKey.1)
            await pause()
            spikeLog.info(
                "self-test created with picked project: current=\(current(), privacy: .public) \(project(), privacy: .public)"
            )

            controller.statusItem?.button?.performClick(nil)
            await pause()
            spikeLog.info("self-test status item click 1: visible=\(panel.isVisible) key=\(panel.isKeyWindow)")
            controller.statusItem?.button?.performClick(nil)
            await pause()
            spikeLog.info("self-test status item click 2: visible=\(panel.isVisible)")
        }
    }

    /// Closes every menu as soon as it opens, records its items and then picks the item titled `pick`.
    @MainActor
    private final class MenuProbe {
        var items: [String] = []
        var pick = ""
        private(set) var closed = 0
        private var index: Int?
        private var observers: [NSObjectProtocol] = []

        init() {
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) {
                    [weak self] note in
                    // posted on the main thread while the menu tracks
                    nonisolated(unsafe) let menu = note.object as? NSMenu
                    MainActor.assumeIsolated {
                        guard let self, let menu else { return }
                        self.items = menu.items.map(\.title)
                        self.index = menu.items.firstIndex { $0.title == self.pick }
                        DispatchQueue.main.async { menu.cancelTracking() }
                    }
                })
            // picking after tracking ended keeps the action out of the menu's event loop
            observers.append(
                center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) {
                    [weak self] note in
                    nonisolated(unsafe) let menu = note.object as? NSMenu
                    MainActor.assumeIsolated {
                        guard let self, let menu else { return }
                        let index = self.index
                        self.index = nil
                        DispatchQueue.main.async {
                            if let index { menu.performActionForItem(at: index) }
                            self.closed += 1
                        }
                    }
                })
        }
    }
#endif
