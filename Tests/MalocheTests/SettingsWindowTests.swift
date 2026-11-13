import AppKit
import MalocheCore
import Testing

@testable import Maloche

/// The settings window is built but never shown, so no keystrokes of the user are taken.
@MainActor @Suite struct SettingsWindowTests {
    @Test func theWindowFitsEachPaneAtTheFixedWidth() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let window = SettingsWindowController(model: model) { _ in }.window
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        #expect(tabs.tabStyle == .toolbar)
        #expect(!window.styleMask.contains(.resizable))
        #expect(tabs.tabViewItems.map(\.label) == ["General", "Schedule", "Rounding", "Backup"])

        var heights: [CGFloat] = []
        for index in tabs.tabViewItems.indices.reversed() {
            tabs.selectedTabViewItemIndex = index
            let content = try #require(window.contentView).frame.size
            let pane = try #require(tabs.tabViewItems[index].view).fittingSize
            #expect(content.width == SettingsWindowController.width)
            #expect(abs(content.height - pane.height) < 1, "pane \(index)")
            heights.append(content.height)
        }
        #expect(heights.allSatisfy { $0 > 80 }, "\(heights)")
        #expect(!window.isVisible)
        #expect(NSApplication.shared.keyWindow == nil)
    }

    /// Control-Tab and Control-Shift-Tab of the hidden menu, as the Window menu of other apps has them.
    @Test func showNextAndPreviousTabSwitchThePanesAround() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let window = SettingsWindowController(model: model) { _ in }.window
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        let menu = MainMenu.make()
        let next = try #require(menu.item(withKey: "\t", modifiers: .control))
        let previous = try #require(menu.item(withKey: "\t", modifiers: [.control, .shift]))
        #expect(window.validateMenuItem(next) && window.validateMenuItem(previous))

        window.perform(next.action, with: next)
        #expect(tabs.selectedTabViewItemIndex == 1)
        window.perform(previous.action, with: previous)
        window.perform(previous.action, with: previous)
        #expect(tabs.selectedTabViewItemIndex == tabs.tabViewItems.count - 1)
        window.perform(next.action, with: next)
        #expect(tabs.selectedTabViewItemIndex == 0)
        #expect(!window.isVisible)
    }

    /// Other windows have no tabs, the keys reach their controls.
    @Test func showNextTabIsOffInOtherWindows() throws {
        let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        let next = try #require(MainMenu.make().item(withKey: "\t", modifiers: .control))
        #expect(!window.validateMenuItem(next))
    }

    @Test func theHiddenMenuClosesWindowsAndEditsText() {
        let menu = MainMenu.make()
        let expected: [(String, NSEvent.ModifierFlags, Selector)] = [
            ("w", .command, #selector(NSWindow.performClose(_:))),
            ("a", .command, #selector(NSText.selectAll(_:))), ("c", .command, #selector(NSText.copy(_:))),
            ("v", .command, #selector(NSText.paste(_:))), ("x", .command, #selector(NSText.cut(_:))),
            ("z", .command, Selector(("undo:"))), ("z", [.command, .shift], Selector(("redo:"))),
        ]
        for (key, modifiers, action) in expected {
            #expect(menu.item(withKey: key, modifiers: modifiers)?.action == action, "\(key)")
        }
    }

    @Test func theBreakShortcutSaysItStartsAndEndsTheBreak() {
        #expect(ShortcutAction.toggleBreak.title == "Start or end break")
    }

    /// D10: the window grows to the pane with the system resize, with Reduce Motion at once.
    @Test func reduceMotionResizesTheWindowAtOnce() {
        #expect(SettingsWindowController.animatesResize(visible: true, reduceMotion: false))
        #expect(!SettingsWindowController.animatesResize(visible: true, reduceMotion: true))
        #expect(!SettingsWindowController.animatesResize(visible: false, reduceMotion: false))
    }

    @Test func recordedModifiersKeepOnlyTheFourShortcutKeys() {
        #expect(Shortcut.Modifiers([.command, .option, .capsLock, .function]) == [.command, .option])
        #expect(Shortcut.Modifiers([.control, .shift, .numericPad]) == [.control, .shift])
    }
}

extension NSMenu {
    /// The item anywhere in the menu with this key equivalent.
    func item(withKey key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        for item in items {
            if item.keyEquivalent == key, item.keyEquivalentModifierMask == modifiers { return item }
            if let found = item.submenu?.item(withKey: key, modifiers: modifiers) { return found }
        }
        return nil
    }
}
