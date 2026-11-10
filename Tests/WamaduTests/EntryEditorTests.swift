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
    }

    private final class Closed {
        var count = 0
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
        let view = EntryEditorView(model: model, activityId: writing, period: period) { closed.count += 1 }
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

    private func press(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                keyCode: keyCode)
            window.sendEvent(event!)
        }
    }

    /// Return for the default button, Command-Delete for Delete.
    private func shortcut(_ characters: String, keyCode: UInt16, command: Bool = false, in window: NSWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0,
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

    @Test func deleteAsksFirstThenDeletesTheEntryAndCloses() throws {
        let (model, writing, window, hosting) = try makeEditor()

        shortcut("\u{8}", keyCode: 51, command: true, in: window)
        settle(hosting)
        #expect(spans(model, writing)?.count == 2)
        #expect(textField(in: hosting, value: time(12, 15)) == nil)
        shortcut("\r", keyCode: 36, in: window)
        settle(hosting)
        #expect(textField(in: hosting, value: time(12, 15)) != nil)
        #expect(closed.count == 0)

        shortcut("\u{8}", keyCode: 51, command: true, in: window)
        settle(hosting)
        shortcut("\u{8}", keyCode: 51, command: true, in: window)
        settle(hosting)
        #expect(model.entry(activityId: writing) == nil)
        #expect(closed.count == 1)
    }

    @Test func doneClosesOnlyTheEditor() throws {
        let (model, writing, window, hosting) = try makeEditor()

        shortcut("\r", keyCode: 36, in: window)
        settle(hosting)

        #expect(closed.count == 1)
        #expect(spans(model, writing)?.count == 2)
    }
}
