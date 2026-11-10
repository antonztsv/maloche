import AppKit
import SwiftUI

/// Never visible for an LSUIElement app, but its key equivalents reach text fields (Cmd+A, C, V, X, Z), Close, Quit
/// and the tabs of the settings.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(
            withTitle: String(localized: "Quit wamadu"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: String(localized: "Window"))
        let previous = window.addItem(
            withTitle: String(localized: "Show Previous Tab"), action: #selector(NSWindow.selectPreviousTab(_:)),
            keyEquivalent: "\t")
        previous.keyEquivalentModifierMask = [.control, .shift]
        let next = window.addItem(
            withTitle: String(localized: "Show Next Tab"), action: #selector(NSWindow.selectNextTab(_:)),
            keyEquivalent: "\t")
        next.keyEquivalentModifierMask = .control

        let menu = NSMenu()
        for submenu in [appMenu, edit, window] {
            menu.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = submenu
        }
        return menu
    }
}

extension View {
    /// A key equivalent without a visible control: an item of a closed menu, a segment of a picker, or Escape, which
    /// reaches no cancelOperation while a button or nothing has the focus.
    func keyCommand(
        _ key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void
    ) -> some View {
        background {
            Button(action: action) { EmptyView() }
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
        }
    }

    /// A Tab stop like a list row, also with keyboard navigation off in System Settings; Space and Return act.
    func keyboardRow(_ action: @escaping () -> Void) -> some View {
        // the button inside leaves the loop, so keyboard navigation on or off gives one stop
        focusable(false)
            .focusable()
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                action()
                return .handled
            }
    }
}
