import AppKit
import SwiftUI
import Testing
import WamaduCore

@testable import Wamadu

/// The Manage Activities window is built but never shown, so no keystrokes of the user are taken.
@MainActor @Suite struct ManageActivitiesWindowTests {
    @Test func theWindowIsANormalResizableWindowOfTheBoardSize() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        _ = try model.database.createActivity(name: "Writing")
        let window = ManageActivitiesWindowController(model: model).window
        #expect(window.identifier == ManageActivitiesWindowController.identifier)
        #expect(window.title == "Manage Activities")
        #expect(window.styleMask.isSuperset(of: [.titled, .closable, .resizable]))
        #expect(try #require(window.contentView).frame.size == ManageActivitiesWindowController.size)
        #expect(window.contentMinSize == ManageActivitiesWindowController.minSize)
        #expect(!window.isVisible)
        #expect(NSApplication.shared.keyWindow == nil)
    }

    /// Keeps the sheets SwiftUI begins instead of showing them.
    private final class Window: NSWindow {
        private var begun: [NSWindow] = []
        private var claimsVisible = false
        override var isVisible: Bool { claimsVisible }

        init() {
            super.init(
                contentRect: NSRect(origin: .zero, size: ManageActivitiesWindowController.size), styleMask: .borderless,
                backing: .buffered, defer: false)
        }

        override func beginSheet(
            _ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil
        ) {
            begun.append(sheetWindow)
        }

        /// The sheet `action` begins; SwiftUI begins sheets of visible windows only, other tests count visible windows.
        func sheet(after action: () -> Void) throws -> NSWindow {
            claimsVisible = true
            defer { claimsVisible = false }
            action()
            return try #require(begun.last)
        }
    }

    /// Acme with the project Website, and Writing without customer.
    private func makeModel() throws -> (AppModel, acme: Int64, writing: Int64) {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        var acme: Int64 = 0
        var writing: Int64 = 0
        try model.manage {
            acme = try $0.createCustomer(name: "Acme").id!
            _ = try $0.createProject(name: "Website", customerId: acme)
            writing = try $0.createActivity(name: "Writing").id!
        }
        return (model, acme, writing)
    }

    private func host(_ view: ManageActivitiesView) -> (Window, NSView) {
        let window = Window()
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        settle(hosting)
        return (window, hosting)
    }

    private func settle(_ view: NSView) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded()
    }

    private func event(_ characters: String, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16, in window: NSWindow)
        -> NSEvent
    {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: keyCode)!
    }

    /// A key as NSApplication dispatches it: offered as a key equivalent first, then sent to the focused view.
    private func press(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        let event = event(characters, [], keyCode: keyCode, in: window)
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }

    private func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    /// The sidebar has one column, the table of activities four.
    private func sidebar(in view: NSView) throws -> NSTableView {
        try #require(views(NSTableView.self, in: view).first { $0.numberOfColumns == 1 })
    }

    private func table(in view: NSView) throws -> NSTableView {
        try #require(views(NSTableView.self, in: view).first { $0.numberOfColumns > 1 })
    }

    /// Types a name into the sheet's field and presses Return there.
    private func enter(_ text: String, in sheet: NSWindow) throws {
        let hosting = try #require(sheet.contentView)
        settle(hosting)
        let field = try #require(views(NSTextField.self, in: hosting).first { $0.isEditable })
        sheet.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        settle(hosting)
        #expect(sheet.performKeyEquivalent(with: event("\r", [], keyCode: 36, in: sheet)))
        settle(hosting)
    }

    @Test func commandFFocusesTheSearch() throws {
        let (window, hosting) = host(ManageActivitiesView(model: try makeModel().0))

        #expect(window.performKeyEquivalent(with: event("f", .command, keyCode: 3, in: window)))
        settle(hosting)

        #expect((window.firstResponder as? NSTextView)?.delegate is NSSearchField)
    }

    @Test func commandNCreatesAnActivity() throws {
        let model = try makeModel().0
        let (window, hosting) = host(ManageActivitiesView(model: model))

        let sheet = try window.sheet {
            #expect(window.performKeyEquivalent(with: event("n", .command, keyCode: 45, in: window)))
            settle(hosting)
        }
        try enter("Kickoff", in: sheet)

        #expect(model.catalog.activities.contains { $0.name == "Kickoff" })
    }

    @Test func returnRenamesTheSelectedActivity() throws {
        let (model, _, writing) = try makeModel()
        let (window, hosting) = host(ManageActivitiesView(model: model, selection: [writing]))
        window.makeFirstResponder(try table(in: hosting))

        let sheet = try window.sheet {
            press("\r", keyCode: 36, in: window)
            settle(hosting)
        }
        try enter("Notes", in: sheet)

        #expect(model.catalog.activities.contains { $0.name == "Notes" })
        #expect(!model.catalog.activities.contains { $0.name == "Writing" })
    }

    @Test func returnInTheSidebarRenamesTheSelectedCustomer() throws {
        let (model, acme, _) = try makeModel()
        let (window, hosting) = host(ManageActivitiesView(model: model, filter: .customer(acme)))
        window.makeFirstResponder(try sidebar(in: hosting))

        let sheet = try window.sheet {
            press("\r", keyCode: 36, in: window)
            settle(hosting)
        }
        try enter("Acme Corp", in: sheet)

        #expect(model.catalog.customer(acme)?.name == "Acme Corp")
    }

    /// Counts the closes a dismiss of its root view asks for, instead of closing.
    private final class Closing: NSWindow {
        var closes = 0
        override func close() { closes += 1 }
    }

    /// Without a focused control Escape reaches no exit command, a key equivalent always reaches Cancel.
    @Test func escapeCancelsTheSheets() throws {
        let sheets: [AnyView] = [
            AnyView(MergeSheet(names: ["Writing"], moving: 3600, targets: []) { _ in }),
            AnyView(NameSheet(title: Text(verbatim: "Rename"), action: Text(verbatim: "Rename")) { _ in }),
        ]
        for sheet in sheets {
            let window = Closing(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered,
                defer: false)
            let hosting = NSHostingView(rootView: sheet)
            window.contentView = hosting
            settle(hosting)

            #expect(window.performKeyEquivalent(with: event("\u{1b}", [], keyCode: 53, in: window)))
            settle(hosting)
            #expect(window.closes == 1)
        }
    }

    /// Other stops in between come from keyboard navigation in System Settings.
    @Test func tabGoesFromTheSidebarToTheSearchToTheTable() throws {
        let (window, hosting) = host(ManageActivitiesView(model: try makeModel().0))
        let sidebar = try sidebar(in: hosting)
        let table = try table(in: hosting)
        window.makeFirstResponder(sidebar)
        var visited = ["sidebar"]

        for _ in 0..<6 {
            // a field takes Tab itself, the lists hand it to the window's key view loop
            if window.firstResponder is NSTextView {
                press("\t", keyCode: 48, in: window)
            } else {
                window.selectNextKeyView(nil)
            }
            settle(hosting)
            let stop: String? =
                switch window.firstResponder {
                case let editor as NSTextView where editor.delegate is NSSearchField: "search"
                case let view as NSView where view === table: "table"
                case let view as NSView where view === sidebar: "sidebar"
                default: nil
                }
            if let stop, stop != visited.last { visited.append(stop) }
        }

        #expect(visited.prefix(4) == ["sidebar", "search", "table", "sidebar"], "\(visited)")
    }
}
