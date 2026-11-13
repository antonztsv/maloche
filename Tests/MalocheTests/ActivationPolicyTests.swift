import AppKit
import Testing

@testable import Maloche

/// Without the Dock setting the app is `.regular` while a window the user opened is visible, `.accessory` otherwise.
@MainActor @Suite struct ActivationPolicyTests {
    private func window(visible: Bool) -> NSWindow {
        final class Probe: NSWindow {
            var shown = false
            override var isVisible: Bool { shown }
        }
        let window = Probe(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        window.shown = visible
        return window
    }

    private func borderless() -> NSWindow {
        final class Probe: NSWindow {
            override var isVisible: Bool { true }
        }
        return Probe(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    }

    @Test func aVisibleNormalWindowCounts() {
        #expect(NSWindow.hasNormalWindow(in: [window(visible: true)], closing: nil))
    }

    @Test func panelsBorderlessHiddenWindowsAndTheClosingOneDoNotCount() {
        let closing = window(visible: true)
        let panel = NSPanel(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        #expect(
            !NSWindow.hasNormalWindow(
                in: [closing, panel, window(visible: false), borderless()], closing: closing))
    }

    @Test func theDockSettingAndOpenWindowsDecideThePolicy() {
        #expect(NSWindow.activationPolicy(showInDock: true, hasNormalWindow: false) == .regular)
        #expect(NSWindow.activationPolicy(showInDock: true, hasNormalWindow: true) == .regular)
        #expect(NSWindow.activationPolicy(showInDock: false, hasNormalWindow: true) == .regular)
        #expect(NSWindow.activationPolicy(showInDock: false, hasNormalWindow: false) == .accessory)
    }
}
