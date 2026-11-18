import AppKit
import MalocheCore
import SwiftUI
import Testing

@testable import Maloche

/// Hosts views in a window that is never shown or key, so no keystrokes of the user are taken.
@MainActor @Suite struct NewProjectFormTests {
    private func host(_ view: some View) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500), styleMask: .borderless, backing: .buffered,
            defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (window, hosting)
    }

    private func textField(in view: NSView, value: String) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue == value { return field }
        return view.subviews.lazy.compactMap { textField(in: $0, value: value) }.first
    }

    private func comboBox(in view: NSView) -> NSComboBox? {
        (view as? NSComboBox) ?? view.subviews.lazy.compactMap { comboBox(in: $0) }.first
    }

    private func items(of comboBox: NSComboBox) -> [String] {
        (0..<comboBox.numberOfItems).compactMap {
            comboBox.dataSource?.comboBox?(comboBox, objectValueForItemAt: $0) as? String
        }
    }

    private func type(_ text: String, in window: NSWindow) {
        for character in text { press(String(character), keyCode: 0, in: window) }
    }

    private static let customers = [
        Customer(id: 1, name: "Acme", colorIndex: 0), Customer(id: 2, name: "Northwind", colorIndex: 1),
        Customer(id: 3, name: "Ångström Labs", colorIndex: 2),
    ]

    /// A key as NSApplication dispatches it: a keyDown is offered as a key equivalent first.
    private func press(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                keyCode: keyCode)!
            if type == .keyUp || !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
        }
    }

    private func settle(_ view: NSView) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded()
    }

    /// Where the text of the field being edited starts, in window coordinates.
    private func textStart(in window: NSWindow) throws -> CGFloat {
        let editor = try #require(window.firstResponder as? NSTextView)
        let x = editor.textContainerOrigin.x + (editor.textContainer?.lineFragmentPadding ?? 0)
        return editor.convert(NSPoint(x: x, y: 0), to: nil).x
    }

    @Test(arguments: ["Acme", "Globex"])
    func theCustomerListIsFlushWithTheField(customer: String) throws {
        let form = NewProjectForm(
            draft: .constant(ProjectDraft(name: "Relaunch", customer: customer)), customers: Self.customers,
            onCancel: {}, onCreate: {})
        let (window, hosting) = host(form)
        settle(hosting)
        let name = try #require(textField(in: hosting, value: "Relaunch"))
        let field = try #require(comboBox(in: hosting))
        // the form pads its fields 4 pt from the window's edges, the name text starts 8 pt into its field
        let fieldMinX: CGFloat = 4
        let fieldMaxX = window.frame.width - 4
        window.makeFirstResponder(name)
        #expect(try textStart(in: window) == fieldMinX + 8)

        // AppKit opens the list 9 pt left and 8 pt right outside the combo box's frame
        let frame = field.convert(field.bounds, to: nil)
        #expect(frame.minX == fieldMinX + 9)
        #expect(frame.maxX == fieldMaxX - 8)
    }

    @Test(arguments: zip(["Globex", "Acme"], [0.0, 14.0]))
    func theCustomerTextStartsWithTheNameText(customer: String, colorSquare: CGFloat) throws {
        let form = NewProjectForm(
            draft: .constant(ProjectDraft(name: "Relaunch", customer: customer)), customers: Self.customers,
            onCancel: {}, onCreate: {})
        let (window, hosting) = host(form)
        settle(hosting)
        let name = try #require(textField(in: hosting, value: "Relaunch"))
        let field = try #require(comboBox(in: hosting))
        window.makeFirstResponder(name)
        let nameStart = try textStart(in: window)

        window.makeFirstResponder(field)

        #expect(abs(try textStart(in: window) - (nameStart + colorSquare)) < 1)
    }

    @Test func theCustomerTextMakesRoomForTheColorSquareWhilePicking() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        _ = try model.createProject(name: "Website", customerName: "Acme")
        let view = CheckInView(
            model: model, content: .checkIn(CheckIn(mode: .manual, span: nil, prefill: nil)),
            draft: ProjectDraft(name: "Relaunch", customer: "Glob"))
        let (window, hosting) = host(view)
        settle(hosting)
        let name = try #require(textField(in: hosting, value: "Relaunch"))
        let field = try #require(comboBox(in: hosting))
        window.makeFirstResponder(name)
        let nameStart = try textStart(in: window)
        window.makeFirstResponder(field)
        #expect(abs(try textStart(in: window) - nameStart) < 1)

        field.selectItem(at: 0)
        settle(hosting)

        // the color square and its spacing
        #expect(abs(try textStart(in: window) - (nameStart + 14)) < 1)
        #expect((window.firstResponder as? NSTextView)?.string == "Acme")
    }

    @Test func creatingAProjectWithANewCustomerKeepsTheCheckIn() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let view = CheckInView(
            model: model, content: .checkIn(CheckIn(mode: .manual, span: nil, prefill: nil)),
            draft: ProjectDraft(name: "Relaunch", customer: "Northwind"))
        let (window, hosting) = host(view)
        let field = try #require(textField(in: hosting, value: "Relaunch"))
        window.makeFirstResponder(field)

        press("\r", keyCode: 36, in: window)
        settle(hosting)

        #expect(model.catalog.projects.map(\.name) == ["Relaunch"])
        #expect(model.catalog.customers.map(\.name) == ["Northwind"])
        #expect(textField(in: hosting, value: "Relaunch") == nil)
    }

    @Test func cancellingTheNewProjectFormCreatesNothingAndKeepsTheCheckIn() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let view = CheckInView(
            model: model, content: .checkIn(CheckIn(mode: .manual, span: nil, prefill: nil)),
            draft: ProjectDraft(name: "Relaunch", customer: "Northwind"))
        let (window, hosting) = host(view)
        let field = try #require(textField(in: hosting, value: "Relaunch"))
        window.makeFirstResponder(field)

        press("\u{1b}", keyCode: 53, in: window)
        settle(hosting)

        #expect(model.catalog.projects.isEmpty)
        #expect(model.catalog.customers.isEmpty)
        #expect(textField(in: hosting, value: "Relaunch") == nil)
    }

    @Test func typingInTheCustomerFieldFiltersTheCustomers() throws {
        var draft = ProjectDraft(name: "Relaunch")
        let form = NewProjectForm(
            draft: Binding(get: { draft }, set: { draft = $0 }), customers: Self.customers, onCancel: {},
            onCreate: {})
        let (window, hosting) = host(form)
        settle(hosting)
        let field = try #require(comboBox(in: hosting))
        #expect(items(of: field) == ["Acme", "Northwind", "Ångström Labs"])
        window.makeFirstResponder(field)

        type("a", in: window)
        settle(hosting)
        #expect(draft.customer == "a")
        #expect(items(of: field) == ["Acme", "Ångström Labs"])

        type("n", in: window)
        settle(hosting)
        #expect(draft.customer == "an")
        #expect(items(of: field) == ["Ångström Labs"])
        #expect(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
    }

    /// A click or Tab into the empty field shows every customer, at most 8 rows before the list scrolls; the list
    /// itself only opens in a visible window.
    @Test func focusingTheCustomerFieldOpensTheWholeList() throws {
        let form = NewProjectForm(
            draft: .constant(ProjectDraft(name: "Relaunch")), customers: Self.customers, onCancel: {}, onCreate: {})
        let (window, hosting) = host(form)
        settle(hosting)
        let field = try #require(comboBox(in: hosting))

        window.makeFirstResponder(field)
        settle(hosting)

        #expect(items(of: field) == ["Acme", "Northwind", "Ångström Labs"])
        #expect(field.numberOfVisibleItems == 8)
        #expect(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
    }

    @Test func aClickOpensTheListOnlyWhenItWasClosedInsideTheFieldWithoutControl() {
        typealias Box = CustomerField.ComboBox
        #expect(Box.shouldOpenList(listOpenAtMouseDown: false, insideField: true, control: false))
        #expect(!Box.shouldOpenList(listOpenAtMouseDown: true, insideField: true, control: false))
        #expect(!Box.shouldOpenList(listOpenAtMouseDown: false, insideField: false, control: false))
        #expect(!Box.shouldOpenList(listOpenAtMouseDown: false, insideField: true, control: true))
    }

    private func customerBox(draft: Binding<ProjectDraft>? = nil) throws -> (NSWindow, NSView, CustomerField.ComboBox) {
        let form = NewProjectForm(
            draft: draft ?? .constant(ProjectDraft(name: "Relaunch")), customers: Self.customers, onCancel: {},
            onCreate: {})
        let (window, hosting) = host(form)
        settle(hosting)
        let box = try #require(comboBox(in: hosting) as? CustomerField.ComboBox)
        return (window, hosting, box)
    }

    @Test func theClickMonitorLivesWhileTheCustomerFieldIsEdited() throws {
        let (window, hosting, box) = try customerBox()
        #expect(!box.isWatchingClicks)

        window.makeFirstResponder(box)
        settle(hosting)
        #expect(box.isWatchingClicks)

        window.makeFirstResponder(nil)
        settle(hosting)
        #expect(!box.isWatchingClicks)
    }

    @Test func theClickMonitorIsGoneWhenTheFieldLeavesTheWindow() throws {
        let (window, hosting, box) = try customerBox()
        window.makeFirstResponder(box)
        settle(hosting)

        box.removeFromSuperview()

        #expect(!box.isWatchingClicks)
    }

    @Test func theClickMonitorSurvivesPickingACustomer() throws {
        var draft = ProjectDraft(name: "Relaunch")
        let (window, hosting, box) = try customerBox(draft: Binding(get: { draft }, set: { draft = $0 }))
        window.makeFirstResponder(box)
        settle(hosting)

        box.selectItem(at: 1)
        settle(hosting)

        #expect(box.currentEditor() != nil)
        #expect(box.isWatchingClicks)
    }

    @Test func pickingACustomerSetsTheDraft() throws {
        var draft = ProjectDraft(name: "Relaunch")
        let form = NewProjectForm(
            draft: Binding(get: { draft }, set: { draft = $0 }), customers: Self.customers, onCancel: {},
            onCreate: {})
        let (_, hosting) = host(form)
        let field = try #require(comboBox(in: hosting))

        field.selectItem(at: 1)
        settle(hosting)

        #expect(draft.customer == "Northwind")
        #expect(field.stringValue == "Northwind")
    }

    @Test func tabMovesFromTheNameToTheCustomerField() throws {
        var draft = ProjectDraft(name: "Relaunch")
        let form = NewProjectForm(
            draft: Binding(get: { draft }, set: { draft = $0 }), customers: Self.customers, onCancel: {},
            onCreate: {})
        let (window, hosting) = host(form)
        let name = try #require(textField(in: hosting, value: "Relaunch"))
        let customer = try #require(comboBox(in: hosting))
        settle(hosting)
        window.makeFirstResponder(name)

        press("\t", keyCode: 48, in: window)
        settle(hosting)

        #expect((window.firstResponder as? NSTextView)?.delegate === customer)
    }

    @Test func returnInTheCustomerFieldCreatesTheProjectWithANewCustomer() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        _ = try model.createProject(name: "Website", customerName: "Acme")
        let view = CheckInView(
            model: model, content: .checkIn(CheckIn(mode: .manual, span: nil, prefill: nil)),
            draft: ProjectDraft(name: "Relaunch"))
        let (window, hosting) = host(view)
        settle(hosting)
        let field = try #require(comboBox(in: hosting))
        window.makeFirstResponder(field)

        type("Globex", in: window)
        press("\r", keyCode: 36, in: window)
        settle(hosting)

        let relaunch = try #require(model.catalog.projects.first { $0.name == "Relaunch" })
        #expect(model.catalog.customer(relaunch.customerId)?.name == "Globex")
        #expect(model.catalog.customers.map(\.name) == ["Acme", "Globex"])
        #expect(comboBox(in: hosting) == nil)
    }

    @Test func escapeInTheCustomerFieldCancelsTheForm() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let view = CheckInView(
            model: model, content: .checkIn(CheckIn(mode: .manual, span: nil, prefill: nil)),
            draft: ProjectDraft(name: "Relaunch", customer: "Northwind"))
        let (window, hosting) = host(view)
        settle(hosting)
        let field = try #require(comboBox(in: hosting))
        window.makeFirstResponder(field)

        press("\u{1b}", keyCode: 53, in: window)
        settle(hosting)

        #expect(model.catalog.projects.isEmpty)
        #expect(model.catalog.customers.isEmpty)
        #expect(comboBox(in: hosting) == nil)
    }
}
