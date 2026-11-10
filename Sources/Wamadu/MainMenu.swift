import AppKit

/// Never visible for an LSUIElement app, but its key equivalents reach text fields (Cmd+A, C, V, X, Z) and Quit.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let appMenu = NSMenu()
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

        let menu = NSMenu()
        menu.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu
        menu.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = edit
        return menu
    }
}
