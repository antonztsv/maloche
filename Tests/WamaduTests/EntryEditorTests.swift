import AppKit
import SwiftUI
import Testing
import WamaduCore

@testable import Wamadu

/// S10: the editor of an entry, hosted in a window that is never shown or key.
@MainActor @Suite struct EntryEditorTests {
    private struct FixedClock: WallClock {
        let now: Date
    }

    private final class Presenter: PanelPresenter {
        var failures = 0
        var isVisible: Bool { true }
        var isKey: Bool { false }
        func show(focus: Bool) {}
        func update() {}
        func focus() {}
        func hide() {}
        func signalFailure() { failures += 1 }
        func showSettings() {}
        func showManageActivities() {}
    }

    /// Whether each close handed the key status back to the dashboard.
    private final class Closed {
        var focusDashboard: [Bool] = []
        var count: Int { focusDashboard.count }
    }

    private let calendar = Calendar.current
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9))!
    private let presenter = Presenter()
    private let closed = Closed()

    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func time(_ hour: Int, _ minute: Int) -> String {
        at(hour, minute).formatted(DashboardData.time)
    }

    /// Writing 10:00 to 12:15 and 16:00 to 17:00, the day's dashboard shown at 18:00.
    private func makeEditor() throws -> (AppModel, Int64, NSWindow, NSView) {
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: FixedClock(now: at(18, 0)))
        model.presenter = presenter
        let writing = try model.database.createActivity(name: "Writing").id!
        for (start, end) in [(at(10, 0), at(12, 15)), (at(16, 0), at(17, 0))] {
            try model.database.insert(
                block: Block(activityId: writing, startedAt: start, endedAt: end, source: .checkIn))
        }
        let period = Period(.day, containing: day, calendar: calendar)
        model.showDashboard(period)
        let closed = closed
        let view = EntryEditorView(model: model, activityId: writing, period: period) {
            closed.focusDashboard.append($0)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless, backing: .buffered,
            defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (model, writing, window, hosting)
    }

    private func spans(_ model: AppModel, _ id: Int64) -> [DateInterval]? {
        model.entry(activityId: id)?.spans.map(\.interval)
    }

    private func textField(in view: NSView, value: String) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue == value { return field }
        return view.subviews.lazy.compactMap { textField(in: $0, value: value) }.first
    }

    /// Selects the field and replaces its text through the field editor, as typing does.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

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

    /// Command-Delete as NSApplication dispatches it: the window's key equivalents first, then the first responder.
    /// The Delete key types U+007F, SwiftUI's `.delete` shortcut is U+0008, the key equivalents get both.
    private func commandDelete(in window: NSWindow) {
        func event(_ type: NSEvent.EventType, _ characters: String) -> NSEvent {
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                keyCode: 51)!
        }
        for characters in ["\u{8}", "\u{7f}"] where window.performKeyEquivalent(with: event(.keyDown, characters)) {
            return
        }
        window.sendEvent(event(.keyDown, "\u{7f}"))
        window.sendEvent(event(.keyUp, "\u{7f}"))
    }

    /// The borderless Delete… is the editor's only AppKit button.
    private func deleteButton(in view: NSView) -> NSButton? {
        (view as? NSButton) ?? view.subviews.lazy.compactMap { deleteButton(in: $0) }.first
    }

    /// Return for the default button.
    private func shortcut(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
        #expect(window.performKeyEquivalent(with: event!))
    }

    private func segmentedControls(in view: NSView) -> [NSSegmentedControl] {
        ((view as? NSSegmentedControl).map { [$0] } ?? []) + view.subviews.flatMap(segmentedControls)
    }

    /// Clicks −15 (segment 0) or +15 (segment 1) of the span.
    private func click(segment: Int, ofSpan span: Int, in view: NSView) throws {
        let controls = segmentedControls(in: view)
        let control = try #require(controls.count > span ? controls[span] : nil)
        // a momentary control keeps no selected segment, its action reads the one being clicked
        let mode = control.trackingMode
        control.trackingMode = .selectOne
        control.selectedSegment = segment
        control.sendAction(control.action, to: control.target)
        control.trackingMode = mode
    }

    private func settle(_ view: NSView) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded()
    }

    /// The text field being edited, through the field editor's delegate.
    private func editedField(in window: NSWindow) -> NSTextField? {
        (window.firstResponder as? NSTextView)?.delegate as? NSTextField
    }

    @Test func theFirstStartTimeHasTheFocusWhenTheEditorOpens() throws {
        let (_, _, window, hosting) = try makeEditor()
        settle(hosting)

        #expect(editedField(in: window)?.stringValue == time(10, 0))
    }

    /// Other stops in between come from keyboard navigation in System Settings, the time fields keep their order.
    @Test func tabGoesThroughTheTimesInReadingOrder() throws {
        let (_, _, window, hosting) = try makeEditor()
        settle(hosting)
        var visited: [String] = editedField(in: window).map { [$0.stringValue] } ?? []

        for _ in 0..<12 {
            press("\t", keyCode: 48, in: window)
            settle(hosting)
            if let field = editedField(in: window), field.stringValue != visited.last {
                visited.append(field.stringValue)
            }
        }

        #expect(visited.prefix(4) == [time(10, 0), time(12, 15), time(16, 0), time(17, 0)], "\(visited)")
    }

    @Test func returnInATimeFieldBooksTheTypedTimeAndCloses() throws {
        let (model, writing, window, hosting) = try makeEditor()
        let end = try #require(textField(in: hosting, value: time(12, 15)))

        try type("12:45", into: end, in: window)
        press("\r", keyCode: 36, in: window)
        settle(hosting)

        #expect(
            spans(model, writing) == [
                DateInterval(start: at(10, 0), end: at(12, 45)), .init(start: at(16, 0), end: at(17, 0)),
            ])
        #expect(closed.count == 1)
        #expect(presenter.failures == 0)
    }

    @Test func anUnreadableTimeRevertsAndBeepsAndTheEditorStays() throws {
        let (model, writing, window, hosting) = try makeEditor()
        let start = try #require(textField(in: hosting, value: time(16, 0)))

        try type("soon", into: start, in: window)
        press("\r", keyCode: 36, in: window)
        settle(hosting)

        #expect(spans(model, writing)?.last == DateInterval(start: at(16, 0), end: at(17, 0)))
        #expect(presenter.failures == 1)
        #expect(closed.count == 0)
        #expect(textField(in: hosting, value: time(16, 0)) != nil)
    }

    @Test func aRefusedTimeRevertsAndBeeps() throws {
        let (model, writing, window, hosting) = try makeEditor()
        let end = try #require(textField(in: hosting, value: time(17, 0)))

        try type("15:00", into: end, in: window)
        press("\r", keyCode: 36, in: window)
        settle(hosting)

        #expect(spans(model, writing)?.last == DateInterval(start: at(16, 0), end: at(17, 0)))
        #expect(presenter.failures == 1)
        #expect(closed.count == 0)
        #expect(textField(in: hosting, value: time(17, 0)) != nil)
    }

    @Test func escapeInATimeFieldClosesWithoutBooking() throws {
        let (model, writing, window, hosting) = try makeEditor()
        let end = try #require(textField(in: hosting, value: time(12, 15)))

        try type("12:45", into: end, in: window)
        press("\u{1b}", keyCode: 53, in: window)
        settle(hosting)

        #expect(spans(model, writing)?.first == DateInterval(start: at(10, 0), end: at(12, 15)))
        #expect(closed.count == 1)
    }

    @Test func theFifteenMinuteButtonsMoveTheEndOfTheirSpan() throws {
        let (model, writing, _, hosting) = try makeEditor()

        try click(segment: 1, ofSpan: 0, in: hosting)
        settle(hosting)
        #expect(spans(model, writing)?.first == DateInterval(start: at(10, 0), end: at(12, 30)))

        try click(segment: 0, ofSpan: 1, in: hosting)
        settle(hosting)
        #expect(spans(model, writing)?.last == DateInterval(start: at(16, 0), end: at(16, 45)))
        #expect(closed.count == 0)
    }

    @Test func deleteAsksFirstAndCancelIsTheDefault() throws {
        let (model, writing, window, hosting) = try makeEditor()

        try #require(deleteButton(in: hosting)).performClick(nil)
        settle(hosting)
        #expect(textField(in: hosting, value: time(12, 15)) == nil)
        commandDelete(in: window)
        settle(hosting)
        #expect(spans(model, writing)?.count == 2)

        shortcut("\r", keyCode: 36, in: window)
        settle(hosting)
        #expect(textField(in: hosting, value: time(12, 15)) != nil)
        #expect(spans(model, writing)?.count == 2)
        #expect(closed.count == 0)
    }

    /// Escape reaches no cancelOperation without a text field, it is a key equivalent like Cancel in a dialog.
    @Test func escapeLeavesTheConfirmationThenClosesTheEditor() throws {
        let (model, writing, window, hosting) = try makeEditor()
        try #require(deleteButton(in: hosting)).performClick(nil)
        settle(hosting)

        shortcut("\u{1b}", keyCode: 53, in: window)
        settle(hosting)
        #expect(textField(in: hosting, value: time(12, 15)) != nil)
        #expect(closed.count == 0)

        window.makeFirstResponder(nil)
        shortcut("\u{1b}", keyCode: 53, in: window)
        settle(hosting)
        #expect(closed.focusDashboard == [true])
        #expect(spans(model, writing)?.count == 2)
    }

    @Test func commandDeleteInATimeFieldNeverAsksOrDeletes() throws {
        let (model, writing, window, hosting) = try makeEditor()
        let end = try #require(textField(in: hosting, value: time(12, 15)))
        window.makeFirstResponder(end)

        for _ in 0..<2 {
            commandDelete(in: window)
            settle(hosting)
        }

        #expect(spans(model, writing)?.count == 2)
        #expect(textField(in: hosting, value: time(16, 0)) != nil)
        #expect(closed.count == 0)
    }

    @Test func aDeletedEntryClosesTheEditorAndTheDashboardTakesTheKeyStatusBack() throws {
        let (model, writing, _, hosting) = try makeEditor()

        // the action of the confirmation's Delete
        model.deleteEntry(try #require(model.entry(activityId: writing)))
        settle(hosting)

        #expect(closed.focusDashboard == [true])
    }

    @Test func aPromptInPlaceOfTheDashboardClosesTheEditorAndLeavesTheKeyStatus() throws {
        let (model, writing, _, hosting) = try makeEditor()

        model.checkIn()
        settle(hosting)

        #expect(spans(model, writing) == nil)
        #expect(closed.focusDashboard == [false])
    }

    @Test func doneClosesOnlyTheEditor() throws {
        let (model, writing, window, hosting) = try makeEditor()

        shortcut("\r", keyCode: 36, in: window)
        settle(hosting)

        #expect(closed.focusDashboard == [true])
        #expect(spans(model, writing)?.count == 2)
    }
}
