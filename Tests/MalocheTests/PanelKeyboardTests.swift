import AppKit
import MalocheCore
import SwiftUI
import Testing

@testable import Maloche

/// The panel by keyboard, hosted in a window that is never shown or key.
@MainActor @Suite struct PanelKeyboardTests {
    /// What the dashboard asked for, in order.
    private final class Calls {
        var periods: [Period] = []
        var selected: [Int64] = []
        var checkIns = 0
        var keepTracking = 0
    }

    private struct FixedClock: WallClock {
        let now: Date
    }

    private final class Presenter: PanelPresenter {
        var settingsShown = 0
        var isVisible: Bool { true }
        var isKey: Bool { true }
        func show(focus: Bool) {}
        func update() {}
        func focus() {}
        func hide() {}
        func signalFailure() {}
        func showSettings() { settingsShown += 1 }
        func showManageActivities(selecting activityId: Int64?) {}
    }

    private let calendar = Calendar.current
    private let calls = Calls()
    /// A Monday seen on the Wednesday after.
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9))!
    private var now: Date { calendar.date(byAdding: .day, value: 2, to: day)! }

    private func at(_ hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    /// Writing 9 to 11 and Review 11 to 12, both without customer.
    private func dashboard(
        _ kind: PeriodKind = .day, current: NowRow = .activity(id: 1), model: AppModel
    ) -> DashboardView {
        let blocks = [
            Block(activityId: 1, startedAt: at(9), endedAt: at(11), source: .checkIn),
            Block(activityId: 2, startedAt: at(11), endedAt: at(12), source: .checkIn),
        ]
        var data = DashboardData(
            period: Period(kind, containing: day, calendar: calendar), blocks: blocks,
            activities: [Activity(id: 1, name: "Writing"), Activity(id: 2, name: "Review")], projects: [],
            customers: [], current: current, now: now, calendar: calendar)
        data.manageable = [1, 2]
        let calls = calls
        return DashboardView(
            data: data, moreActions: MoreActionsMenu(model: model), onShowPeriod: { calls.periods.append($0) },
            onCheckIn: { calls.checkIns += 1 }, onKeepTracking: { calls.keepTracking += 1 },
            onSelect: { calls.selected.append($0) })
    }

    private func host(_ view: some View) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 700), styleMask: .borderless, backing: .buffered,
            defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
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

    /// A key equivalent as NSApplication hands it to the key window.
    private func command(_ characters: String, keyCode: UInt16, in window: NSWindow) -> Bool {
        window.performKeyEquivalent(with: event(characters, .command, keyCode: keyCode, in: window))
    }

    /// A key as NSApplication dispatches it: offered as a key equivalent first, then sent to the focused view.
    private func press(_ characters: String, keyCode: UInt16, in window: NSWindow) {
        let event = event(characters, [], keyCode: keyCode, in: window)
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }

    private static let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    private static let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)

    @Test func commandArrowsPageThroughTheDays() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let (window, _) = host(dashboard(model: model))
        let period = Period(.day, containing: day, calendar: calendar)

        #expect(command(Self.left, keyCode: 123, in: window))
        #expect(command(Self.right, keyCode: 124, in: window))

        #expect(calls.periods == [period.previous(calendar: calendar), period.next(calendar: calendar)])
    }

    @Test(arguments: [("1", UInt16(18), PeriodKind.day), ("2", 19, .week), ("3", 20, .month)])
    func commandDigitsSwitchThePeriod(key: String, keyCode: UInt16, kind: PeriodKind) throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let shown: PeriodKind = kind == .week ? .month : .week
        let (window, _) = host(dashboard(shown, model: model))

        #expect(command(key, keyCode: keyCode, in: window))

        let period = Period(shown, containing: day, calendar: calendar)
        #expect(calls.periods == [period.switched(to: kind, now: now, calendar: calendar)])
    }

    /// The dashboard opens with the panel itself as first responder, no row shows a focus ring until Tab.
    @Test func theDashboardStartsWithoutAFocusedElementAndTabFocusesTheFirst() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let (window, hosting) = host(dashboard(model: model))
        window.makeFirstResponder(window.contentView?.nextValidKeyView)
        settle(hosting)
        #expect(window.firstResponder !== hosting)

        #expect(CheckInPanelController.startWithoutFocus(in: window, hosting: hosting))
        #expect(window.firstResponder === hosting)

        window.selectNextKeyView(nil)
        settle(hosting)
        #expect(window.firstResponder !== hosting)
    }

    /// Walks back from the end, the Now row and the rows come before anything above them.
    @Test func rowsAndTheNowRowAreInTheTabLoopAndReturnOpensThem() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let (window, hosting) = host(dashboard(model: model))
        window.makeFirstResponder(hosting)

        window.selectPreviousKeyView(nil)
        settle(hosting)
        press("\r", keyCode: 36, in: window)
        #expect(calls.checkIns == 1)

        for _ in 0..<2 {
            window.selectPreviousKeyView(nil)
            settle(hosting)
            press(" ", keyCode: 49, in: window)
        }
        settle(hosting)
        #expect(calls.selected == [2, 1])
    }

    /// Escape reaches no cancelOperation without a text field, it is a key equivalent like Cancel in a dialog.
    @Test func escapeClosesTheDashboard() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: FixedClock(now: now))
        model.showDashboard(Period(.day, containing: day, calendar: calendar))
        let (window, hosting) = host(PanelView(model: model, onResize: {}))
        window.makeFirstResponder(hosting)
        window.selectPreviousKeyView(nil)
        settle(hosting)

        #expect(window.performKeyEquivalent(with: event("\u{1b}", [], keyCode: 53, in: window)))

        #expect(model.panel == nil)
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
    }

    /// With keyboard navigation on, Tab moves the focus from the field to the buttons.
    @Test func escapeWithoutTheFieldFocusedClosesTheCheckIn() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        model.checkIn()
        let content = try #require(model.panel)
        let (window, hosting) = host(CheckInView(model: model, content: content))
        window.makeFirstResponder(nil)

        #expect(window.performKeyEquivalent(with: event("\u{1b}", [], keyCode: 53, in: window)))
        settle(hosting)

        #expect(model.panel == nil)
    }

    @Test func escapeWithoutAFieldFocusedLeavesTheSplit() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let span = DateInterval(start: at(9), end: at(10))
        let checkIn = CheckIn(mode: .timed, span: span, prefill: nil, canSplit: true)
        let list = CheckInList(catalog: model.catalog, prefill: nil)
        let (window, hosting) = host(
            CheckInView(
                model: model, content: .checkIn(checkIn), split: SplitDraft(span: span, first: list, second: list)))
        #expect(textFields(in: hosting).count == 2)
        window.makeFirstResponder(nil)

        #expect(window.performKeyEquivalent(with: event("\u{1b}", [], keyCode: 53, in: window)))
        settle(hosting)

        #expect(textFields(in: hosting).count == 1)
    }

    @Test(arguments: [NowRow.off, .doneForToday])
    func keepTrackingIsInTheTabLoop(current: NowRow) throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let (window, hosting) = host(dashboard(current: current, model: model))
        window.makeFirstResponder(hosting)

        window.selectPreviousKeyView(nil)
        settle(hosting)
        press("\r", keyCode: 36, in: window)

        #expect(calls.keepTracking == 1)
        #expect(calls.checkIns == 0)
    }

    @Test func returnOnKeepTrackingOfAFreshDayResumesTrackingWithoutACheckIn() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: FixedClock(now: now))
        model.showDashboard(Period(.day, containing: now, calendar: calendar))
        #expect(model.nowRow == .off)
        let (window, hosting) = host(PanelView(model: model, onResize: {}))
        window.makeFirstResponder(hosting)
        window.selectPreviousKeyView(nil)
        settle(hosting)

        press("\r", keyCode: 36, in: window)
        settle(hosting)

        #expect(model.mode == .tracking)
        #expect(model.panel?.isPrompt == false)
    }

    @Test func commandCommaOpensTheSettingsWithTheMenuClosed() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let presenter = Presenter()
        model.presenter = presenter
        let (window, _) = host(dashboard(model: model))

        #expect(command(",", keyCode: 43, in: window))

        #expect(presenter.settingsShown == 1)
    }
}
