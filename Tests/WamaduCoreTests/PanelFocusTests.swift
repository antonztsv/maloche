import Testing

@testable import WamaduCore

@Suite struct PanelFocusTests {
    @Test func timerShowsWithoutTakingFocus() {
        #expect(PanelFocus.action(for: .timer, visible: false, key: false) == .show(focus: false))
        #expect(PanelFocus.action(for: .timer, visible: true, key: false) == .update)
        #expect(PanelFocus.action(for: .timer, visible: true, key: true) == .update)
    }

    @Test func statusItemOpensFocusedFocusesAnUnfocusedPanelAndClosesAFocusedOne() {
        #expect(PanelFocus.action(for: .statusItem, visible: false, key: false) == .show(focus: true))
        #expect(PanelFocus.action(for: .statusItem, visible: true, key: false) == .focus)
        #expect(PanelFocus.action(for: .statusItem, visible: true, key: true) == .close)
    }

    @Test func shortcutOpensFocusedAndFocusesAnOpenPanel() {
        #expect(PanelFocus.action(for: .shortcut, visible: false, key: false) == .show(focus: true))
        #expect(PanelFocus.action(for: .shortcut, visible: true, key: false) == .focus)
        #expect(PanelFocus.action(for: .shortcut, visible: true, key: true) == .focus)
    }

    @Test func theEditorStaysWhileItIsKeyAClickIntoTheDashboardClosesOnlyTheEditorAnotherAppClosesBoth() {
        func outcome(_ key: String?) -> PanelFocus.Outcome {
            PanelFocus.afterResignKey(key: key, dashboard: "dashboard", editor: "editor")
        }
        #expect(outcome("editor") == .keep)
        #expect(outcome("dashboard") == .closeEditor)
        #expect(outcome(nil) == .closeAll)
        #expect(outcome("other app") == .closeAll)
    }
}
