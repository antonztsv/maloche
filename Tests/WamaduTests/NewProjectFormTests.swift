import AppKit
import SwiftUI
import Testing
import WamaduCore

@testable import Wamadu

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

    private func press(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                keyCode: keyCode)
            window.sendEvent(event!)
        }
    }

    private func settle(_ view: NSView) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded()
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
