#if DEBUG
    import AppKit

    /// Sends key events to the panel in-process, no accessibility permission needed.
    @MainActor
    enum SpikeSelfTest {
        static func run(_ controller: CheckInPanelController, panel: NSPanel) async {
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
            func pause() async { try? await Task.sleep(for: .milliseconds(400)) }

            controller.open(.timer)
            await pause()
            spikeLog.info("self-test timer: key=\(panel.isKeyWindow) visible=\(panel.isVisible)")
            controller.open(.shortcut)
            await pause()
            let focused = panel.firstResponder as? NSTextView
            spikeLog.info(
                """
                self-test shortcut focuses: key=\(panel.isKeyWindow) \
                selection=\(focused.map { NSStringFromRange($0.selectedRange()) } ?? "-", privacy: .public)
                """)
            key("\u{1b}", 53)
            await pause()
            spikeLog.info("self-test escape: visible=\(panel.isVisible)")

            controller.open(.statusItem)
            await pause()
            key("x", 7)
            spikeLog.info(
                "self-test field text: \((panel.firstResponder as? NSTextView)?.string ?? "-", privacy: .public)")
            key("a", 0, .command)
            let editor = panel.firstResponder as? NSTextView
            spikeLog.info(
                "self-test cmd-a: selection=\(editor.map { NSStringFromRange($0.selectedRange()) } ?? "-", privacy: .public)"
            )
            key("\r", 36)
            await pause()
            spikeLog.info("self-test typed x and return: visible=\(panel.isVisible)")

            controller.statusItem?.button?.performClick(nil)
            await pause()
            spikeLog.info("self-test status item click 1: visible=\(panel.isVisible) key=\(panel.isKeyWindow)")
            controller.statusItem?.button?.performClick(nil)
            await pause()
            spikeLog.info("self-test status item click 2: visible=\(panel.isVisible)")
        }
    }
#endif
