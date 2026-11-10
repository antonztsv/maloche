import AppKit
import Testing
import WamaduCore

@testable import Wamadu

/// The settings window is built but never shown, so no keystrokes of the user are taken.
@MainActor @Suite struct SettingsWindowTests {
    @Test func theWindowFitsEachPaneAtTheFixedWidth() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let window = SettingsWindowController(model: model) { _ in }.window
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        #expect(tabs.tabStyle == .toolbar)
        #expect(tabs.tabViewItems.map(\.label) == ["General", "Schedule", "Rounding"])

        var heights: [CGFloat] = []
        for index in tabs.tabViewItems.indices.reversed() {
            tabs.selectedTabViewItemIndex = index
            let content = try #require(window.contentView).frame.size
            let pane = try #require(tabs.tabViewItems[index].view).fittingSize
            #expect(content.width == SettingsWindowController.width)
            #expect(abs(content.height - pane.height) < 1, "pane \(index)")
            heights.append(content.height)
        }
        #expect(heights.allSatisfy { $0 > 150 })
        #expect(!window.isVisible)
        #expect(NSApplication.shared.keyWindow == nil)
    }

    @Test func recordedModifiersKeepOnlyTheFourShortcutKeys() {
        #expect(Shortcut.Modifiers([.command, .option, .capsLock, .function]) == [.command, .option])
        #expect(Shortcut.Modifiers([.control, .shift, .numericPad]) == [.control, .shift])
    }
}
