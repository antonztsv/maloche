import AppKit
import Testing

@testable import Maloche

/// Without a Dock icon the app is `.regular` while a window the user opened is visible, `.accessory` otherwise.
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

    @Test func aVisibleNormalWindowNeedsTheRegularPolicy() {
        #expect(NSWindow.activationPolicy(for: [window(visible: true)], closing: nil) == .regular)
    }

    @Test func panelsHiddenWindowsAndTheClosingOneDoNotCount() {
        let closing = window(visible: true)
        let panel = NSPanel(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        #expect(
            NSWindow.activationPolicy(for: [closing, panel, window(visible: false)], closing: closing) == .accessory)
    }
}
