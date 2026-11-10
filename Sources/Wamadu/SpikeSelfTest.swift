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
            key("a", 0, .command)
            spikeLog.info(
                "self-test cmd-a: field=\(field(), privacy: .public) selection=\(selection(), privacy: .public)")
            key("\u{1b}", 53)
            await pause()

            controller.statusItem?.button?.performClick(nil)
            await pause()
            spikeLog.info("self-test status item click 1: visible=\(panel.isVisible) key=\(panel.isKeyWindow)")
            controller.statusItem?.button?.performClick(nil)
            await pause()
            spikeLog.info("self-test status item click 2: visible=\(panel.isVisible)")
        }
    }
#endif
