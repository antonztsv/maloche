import Testing

@testable import MalocheCore

@Suite struct PanelFocusTests {
    @Test func timerShowsWithoutTakingFocus() {
        #expect(PanelFocus.action(for: .timer, visible: false, key: false) == .show(focus: false))
        #expect(PanelFocus.action(for: .timer, visible: true, key: false) == .update)
        #expect(PanelFocus.action(for: .timer, visible: true, key: true) == .update)
    }

    @Test func statusItemOpensFocusedAndClosesAVisiblePanelFocusedOrNot() {
        #expect(PanelFocus.action(for: .statusItem, visible: false, key: false) == .show(focus: true))
        #expect(PanelFocus.action(for: .statusItem, visible: true, key: false) == .close)
        #expect(PanelFocus.action(for: .statusItem, visible: true, key: true) == .close)
    }

    @Test func shortcutOpensFocusedAndFocusesAnOpenPanel() {
        #expect(PanelFocus.action(for: .shortcut, visible: false, key: false) == .show(focus: true))
        #expect(PanelFocus.action(for: .shortcut, visible: true, key: false) == .focus)
        #expect(PanelFocus.action(for: .shortcut, visible: true, key: true) == .focus)
    }
}
