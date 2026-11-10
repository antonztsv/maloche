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
}
