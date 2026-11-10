import Foundation
import GRDB
import Observation
import Testing

@testable import WamaduCore

@MainActor
final class FakePresenter: PanelPresenter {
    var isVisible = false
    var isKey = false
    var calls: [String] = []
    var failures = 0

    func show(focus: Bool) {
        isVisible = true
        isKey = focus
        calls.append("show(focus: \(focus))")
    }

    func update() { calls.append("update") }

    func focus() {
        isKey = true
        calls.append("focus")
    }

    func hide() {
        isVisible = false
        isKey = false
        calls.append("hide")
    }

    func signalFailure() { failures += 1 }
}

final class TestClock: WallClock, @unchecked Sendable {
    var now: Date

    init(_ time: String) { now = Fixture.at(time) }
}

@MainActor @Suite struct AppModelTests {
    private let clock = TestClock("09:00")
    private let presenter = FakePresenter()

    private func makeModel(_ database: AppDatabase? = nil, stateURL: URL? = nil) throws -> AppModel {
        let model = try AppModel(
            database: database ?? .inMemory(), stateURL: stateURL, clock: clock, calendar: Fixture.berlin)
        model.presenter = presenter
        return model
    }

    /// Present at `time`: the user worked right up to it.
    private func tick(_ model: AppModel, at time: String) {
        clock.now = Fixture.at(time)
        model.send(.tick(idleSeconds: 0))
    }

    /// Blocks of the day with adjacent blocks of one activity merged, as "Writing 09:00-09:10".
    private func timeline(_ model: AppModel) throws -> [String] {
        let names = Dictionary(uniqueKeysWithValues: try model.database.activities().map { ($0.id!, $0.name) })
        var merged: [Block] = []
        for block in try model.database.blocks(in: DateInterval(start: Fixture.at("00:00"), end: Fixture.at("23:59"))) {
            if let last = merged.last, last.activityId == block.activityId, last.endedAt == block.startedAt {
                merged[merged.count - 1].endedAt = block.endedAt
            } else {
                merged.append(block)
            }
        }
        return merged.map { "\(names[$0.activityId]!) \(Fixture.clock($0.startedAt))-\(Fixture.clock($0.endedAt))" }
    }

    @Test func ticksThatChangeNothingVisibleDoNotRedrawTheMenuOrIcon() throws {
        let model = try makeModel()
        _ = try model.database.createActivity(name: "Writing")
        tick(model, at: "09:00")
        final class Flag: @unchecked Sendable { var changed = false }
        let flag = Flag()
        withObservationTracking {
            _ = model.mode
            _ = model.nowRow
            _ = model.activityToContinue
            _ = model.schedule
        } onChange: {
            flag.changed = true
        }
        tick(model, at: "09:01")
        tick(model, at: "09:02")
        #expect(!flag.changed)
        model.send(.startBreak)
        #expect(flag.changed)
        #expect(model.mode == .onBreak)
    }

    @Test func checkInShortcutOpensTheCheckInByHandAndTheAnswerStartsNow() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:00")

        clock.now = Fixture.at("09:10")
        model.shortcut(.openCheckIn)
        #expect(presenter.calls == ["show(focus: true)"])
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:00", "09:10"), prefill: nil)))
        model.log(.existing(writing))
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")

        clock.now = Fixture.at("09:12")
        model.shortcut(.openCheckIn)
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:10", "09:12"), prefill: writing)))
        model.log(.existing(reading))
        tick(model, at: "09:14")
        #expect(try timeline(model) == ["Writing 09:00-09:12", "Reading 09:12-09:14"])
        #expect(model.catalog.usedToday == [reading, writing])
    }

    @Test func aTimedPromptShowsWithoutFocusAndItsAnswerCoversTheSpan() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))

        tick(model, at: "09:15")
        #expect(presenter.calls.last == "show(focus: false)")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
        model.log(.existing(reading))
        #expect(model.panel == nil)
        #expect(try timeline(model) == ["Writing 09:00-09:07:30", "Reading 09:07:30-09:15"])
    }

    @Test func aDueCheckInTurnsAnOpenManualCheckInIntoTheTimedOne() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))

        clock.now = Fixture.at("09:14")
        model.shortcut(.openCheckIn)
        tick(model, at: "09:15")
        #expect(presenter.calls.suffix(2) == ["show(focus: true)", "update"])
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
    }

    @Test func escapeDismissesATimedPromptAndOnlyClosesAManualOne() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))

        clock.now = Fixture.at("09:05")
        model.shortcut(.openCheckIn)
        let before = model.tracker.state
        model.close()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(model.tracker.state == before)

        tick(model, at: "09:15")
        #expect(model.tracker.state.checkInShown)
        model.close()
        #expect(model.panel == nil)
        #expect(!model.tracker.state.checkInShown)
    }

    @Test func iconClickFocusesAnUnfocusedPromptAndClosesAFocusedOne() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        tick(model, at: "09:15")

        model.statusItemClicked()
        #expect(presenter.calls.last == "focus")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
        model.statusItemClicked()
        #expect(presenter.calls.last == "hide")
        #expect(!model.tracker.state.checkInShown)
    }

    @Test func breakClosesThePanelAndStartsABreak() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))

        clock.now = Fixture.at("09:10")
        model.shortcut(.openCheckIn)
        model.startBreak()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(model.tracker.mode == .onBreak)
    }

    @Test func breakShortcutDuringABreakAsksAboutTheBreakFocused() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        clock.now = Fixture.at("09:05")
        model.send(.startBreak)

        clock.now = Fixture.at("09:20")
        model.shortcut(.toggleBreak)
        #expect(model.tracker.state.phase == .breakReturn(returnAt: Fixture.at("09:20")))
        #expect(model.panel == .breakReturn(span: Fixture.span("09:05", "09:20"), prefill: writing))
        #expect(presenter.calls.suffix(2) == ["show(focus: false)", "focus"])
    }

    // MARK: Dashboard

    /// Writing from 09:00, answered through the check-in shortcut.
    private func writingFrom0900(_ model: AppModel) throws -> Int64 {
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        return writing
    }

    private func shownDay(_ model: AppModel) -> DashboardDay? {
        if case .dashboard(let day) = model.panel { day } else { nil }
    }

    private var today: Period { Period(.day, containing: Fixture.at("09:00"), calendar: Fixture.berlin) }

    @Test func iconClickOpensTodaysDashboardFocusedAndClosesItWhenFocused() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        tick(model, at: "09:10")
        presenter.calls = []

        model.statusItemClicked()
        #expect(presenter.calls == ["show(focus: true)"])
        #expect(shownDay(model)?.period == today)
        #expect(shownDay(model)?.blocks.map(\.endedAt) == [Fixture.at("09:10")])
        let before = model.tracker.state
        model.statusItemClicked()
        #expect(presenter.calls.last == "hide")
        #expect(model.panel == nil)
        #expect(model.tracker.state == before)
    }

    @Test func theNowRowOpensTheCheckInByHandAndLogGoesBackToTheDashboard() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        let reading = try model.database.createActivity(name: "Reading").id!
        clock.now = Fixture.at("09:10")
        model.statusItemClicked()
        presenter.calls = []

        model.checkIn()
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:00", "09:10"), prefill: writing)))
        model.log(.existing(reading))
        #expect(presenter.calls.isEmpty)
        #expect(shownDay(model)?.period == today)
        #expect(shownDay(model)?.blocks.map(\.activityId) == [writing])
        #expect(model.nowRow == .activity(id: reading))
        #expect(model.tracker.currentActivity == reading)
    }

    @Test func checkInNowOnAFreshDayOpensTheCheckInByHand() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        #expect(shownDay(model)?.blocks == [])
        #expect(model.nowRow == .none)

        clock.now = Fixture.at("09:05")
        model.checkIn()
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:00", "09:05"), prefill: nil)))
        model.log(.existing(writing))
        #expect(shownDay(model)?.blocks.map(\.activityId) == [writing])
    }

    @Test func theNowRowFollowsTheTracker() throws {
        let model = try makeModel()
        #expect(model.nowRow == .off)
        tick(model, at: "09:00")
        #expect(model.nowRow == .none)
        let writing = try writingFrom0900(model)
        #expect(model.nowRow == .activity(id: writing))
        model.continueWithoutAsking(for: nil)
        #expect(model.nowRow == .activity(id: writing))
        model.startBreak()
        #expect(model.nowRow == .onBreak)
        model.turnOff(for: nil)
        #expect(model.nowRow == .off)
    }

    @Test func aClickOnTheIconDuringABreakShowsTheDashboardAndTheBreakRowAsksAboutTheBreak() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        let reading = try model.database.createActivity(name: "Reading").id!
        clock.now = Fixture.at("09:05")
        model.startBreak()

        clock.now = Fixture.at("09:20")
        model.statusItemClicked()
        #expect(shownDay(model) != nil)
        #expect(model.nowRow == .onBreak)
        #expect(model.tracker.state.phase == .onBreak(awaySince: nil))

        model.checkIn()
        #expect(model.panel == .breakReturn(span: Fixture.span("09:05", "09:20"), prefill: writing))
        model.log(.existing(reading))
        #expect(shownDay(model) != nil)
        #expect(model.nowRow == .activity(id: reading))
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Break 09:05-09:20"])
    }

    @Test func pagingShowsTheBlocksOfThatDay() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        try model.database.insert(
            block: Block(
                activityId: writing, startedAt: Fixture.at("2026-11-08 10:00"), endedAt: Fixture.at("2026-11-08 11:00"),
                source: .checkIn))
        tick(model, at: "09:10")
        model.statusItemClicked()

        let yesterday = today.previous(calendar: Fixture.berlin)
        model.showDashboard(yesterday)
        #expect(shownDay(model)?.period == yesterday)
        #expect(shownDay(model)?.blocks.map(\.startedAt) == [Fixture.at("2026-11-08 10:00")])
        model.showDashboard(today)
        #expect(shownDay(model)?.blocks.map(\.startedAt) == [Fixture.at("09:00")])
    }

    @Test func theDashboardRefreshesAfterABooking() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        clock.now = Fixture.at("09:01")
        model.statusItemClicked()
        #expect(shownDay(model)?.blocks == [])
        tick(model, at: "09:05")
        #expect(shownDay(model)?.blocks.map(\.endedAt) == [Fixture.at("09:05")])
    }

    @Test func aTimedCheckInOverTheDashboardGoesBackToItOnceAnswered() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        clock.now = Fixture.at("09:14")
        model.statusItemClicked()
        tick(model, at: "09:15")
        #expect(presenter.calls.last == "update")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
        model.log(.existing(writing))
        #expect(shownDay(model)?.blocks.map(\.endedAt) == [Fixture.at("09:15")])
    }

    @Test func escapeOnACheckInOpenedFromTheDashboardGoesBackToIt() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        model.statusItemClicked()
        model.checkIn()
        model.close()
        #expect(shownDay(model)?.period == today)
        #expect(presenter.isVisible)
    }

    @Test func escapeOnATimedCheckInOverTheDashboardDismissesItAndGoesBack() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        clock.now = Fixture.at("09:14")
        model.statusItemClicked()
        tick(model, at: "09:15")
        model.close()
        #expect(shownDay(model)?.period == today)
        #expect(presenter.isVisible)
        #expect(!model.tracker.state.checkInShown)
    }

    @Test func iconClickOnAFocusedPromptOverTheDashboardClosesThePanel() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        model.statusItemClicked()
        model.checkIn()
        model.statusItemClicked()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
    }

    @Test func aPromptTheTrackerEndsGoesBackToTheDashboard() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        clock.now = Fixture.at("09:14")
        model.statusItemClicked()
        tick(model, at: "09:15")
        #expect(model.panel?.isPrompt == true)
        clock.now = Fixture.at("09:16")
        model.send(.systemAway(since: Fixture.at("09:15")))
        #expect(shownDay(model)?.blocks.map(\.endedAt) == [Fixture.at("09:15")])
        #expect(presenter.isVisible)
    }

    // MARK: More menu

    @Test func doneForTodayClosesThePanelAndTheIconShowsThatsItUntilKeepTracking() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        clock.now = Fixture.at("17:00")
        model.shortcut(.openCheckIn)

        model.doneForToday()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(model.tracker.mode == .off)
        #expect(try timeline(model) == ["Writing 09:00-17:00"])

        clock.now = Fixture.at("17:05")
        model.statusItemClicked()
        let blocks = try model.database.blocks(in: today.interval)
        #expect(model.panel == .doneForToday(DashboardDay(period: today, blocks: blocks)))
        model.keepTracking()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(model.tracker.mode == .tracking)
        #expect(model.nowRow == .activity(id: writing))

        model.statusItemClicked()
        #expect(shownDay(model)?.period == today)
    }

    @Test func afterTurnOffTheDashboardSaysTrackingIsOffAndKeepTrackingKeepsIt() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        clock.now = Fixture.at("12:00")
        model.turnOff(for: nil)

        tick(model, at: "13:00")
        model.statusItemClicked()
        #expect(shownDay(model) != nil)
        #expect(model.nowRow == .off)
        model.keepTracking()
        #expect(shownDay(model) != nil)
        #expect(model.tracker.mode == .tracking)
        #expect(model.nowRow == .activity(id: writing))
    }

    @Test func turnOffAndTurnOnFromTheMenu() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        clock.now = Fixture.at("09:10")
        model.turnOff(for: 30 * 60)
        #expect(model.tracker.state.phase == .off(until: Fixture.at("09:40")))
        #expect(model.tracker.mode == .off)
        model.turnOn()
        #expect(model.tracker.mode == .tracking)

        model.turnOff(for: nil)
        #expect(model.tracker.state.phase == .off(until: nil))
        model.turnOn()
        #expect(model.tracker.mode == .tracking)

        model.doneForToday()
        model.turnOn()
        #expect(model.tracker.mode == .tracking)
    }

    @Test func continueWithoutAskingKeepsLoggingTheRunningActivity() throws {
        let model = try makeModel()
        #expect(model.activityToContinue == nil)
        let writing = try writingFrom0900(model)
        #expect(model.activityToContinue == writing)

        clock.now = Fixture.at("09:10")
        model.continueWithoutAsking(for: 2 * 3600)
        #expect(model.tracker.state.phase == .continuing(until: Fixture.at("11:10")))
        #expect(model.tracker.mode == .continuing)
        model.stopContinuing()
        #expect(model.tracker.mode == .tracking)
        model.continueWithoutAsking(for: nil)
        #expect(model.tracker.state.phase == .continuing(until: nil))

        model.startBreak()
        #expect(model.activityToContinue == nil)
    }

    @Test func everyMenuActionClosesTheDashboard() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        let actions: [(name: String, run: () -> Void, mode: TrackerMode)] = [
            ("turn off", { model.turnOff(for: nil) }, .off),
            ("turn on", { model.turnOn() }, .tracking),
            ("continue", { model.continueWithoutAsking(for: 3600) }, .continuing),
            ("stop continuing", { model.stopContinuing() }, .tracking),
            ("done for today", { model.doneForToday() }, .off),
        ]
        for action in actions {
            model.statusItemClicked()
            #expect(shownDay(model) != nil, "\(action.name)")
            action.run()
            #expect(model.panel == nil, "\(action.name)")
            #expect(!presenter.isVisible, "\(action.name)")
            #expect(model.tracker.mode == action.mode, "\(action.name)")
        }
    }

    @Test func aMenuActionOnATimedCheckInOverTheDashboardClosesThePanelWithoutLosingTime() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        clock.now = Fixture.at("09:10")
        model.statusItemClicked()
        tick(model, at: "09:15")
        #expect(model.panel?.isPrompt == true)

        model.continueWithoutAsking(for: 3600)
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(!model.tracker.state.checkInShown)
        clock.now = Fixture.at("09:30")
        model.stopContinuing()
        #expect(try timeline(model) == ["Writing 09:00-09:30"])
    }

    @Test func aMenuActionOnTheAwayReturnCountsItAsDismissed() throws {
        let model = try makeModel()
        _ = try backFromAway(model)
        model.continueWithoutAsking(for: nil)
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        clock.now = Fixture.at("09:52")
        model.stopContinuing()
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Break 09:05-09:50", "Writing 09:50-09:52"])
    }

    // MARK: Shortcuts

    @Test func checkInShortcutFocusesAVisiblePromptAndTurnsTheDashboardIntoACheckIn() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        tick(model, at: "09:15")
        #expect(presenter.calls.last == "show(focus: false)")
        model.shortcut(.openCheckIn)
        #expect(presenter.calls.last == "focus")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
        model.log(.existing(writing))

        clock.now = Fixture.at("09:20")
        model.statusItemClicked()
        model.shortcut(.openCheckIn)
        #expect(presenter.calls.last == "focus")
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:00", "09:20"), prefill: writing)))
    }

    @Test func checkInShortcutDuringABreakAsksAboutTheBreak() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        clock.now = Fixture.at("09:05")
        model.startBreak()
        clock.now = Fixture.at("09:20")
        model.shortcut(.openCheckIn)
        #expect(model.panel == .breakReturn(span: Fixture.span("09:05", "09:20"), prefill: writing))
        #expect(presenter.calls.suffix(2) == ["show(focus: false)", "focus"])
    }

    @Test func breakShortcutStartsABreakWhileTrackingOrContinuingAndDoesNothingWhileOff() throws {
        let model = try makeModel()
        model.shortcut(.toggleBreak)
        #expect(model.tracker.mode == .off)
        _ = try writingFrom0900(model)
        presenter.calls = []

        clock.now = Fixture.at("09:10")
        model.shortcut(.toggleBreak)
        #expect(model.tracker.mode == .onBreak)
        #expect(presenter.calls.isEmpty)
        clock.now = Fixture.at("09:20")
        model.shortcut(.toggleBreak)
        model.log(.existing(model.tracker.currentActivity!))

        model.continueWithoutAsking(for: nil)
        clock.now = Fixture.at("09:30")
        model.statusItemClicked()
        model.shortcut(.toggleBreak)
        #expect(model.tracker.mode == .onBreak)
        #expect(shownDay(model) != nil)
        #expect(model.nowRow == .onBreak)

        model.turnOff(for: nil)
        presenter.calls = []
        model.shortcut(.toggleBreak)
        #expect(model.tracker.mode == .off)
        #expect(presenter.calls.isEmpty)
    }

    @Test func dashboardShortcutOpensTheDashboardAndNeverCloses() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        presenter.calls = []
        model.shortcut(.openDashboard)
        #expect(presenter.calls == ["show(focus: true)"])
        #expect(shownDay(model)?.period == today)
        model.shortcut(.openDashboard)
        #expect(presenter.calls.last == "focus")
        #expect(shownDay(model) != nil)
    }

    @Test func dashboardShortcutOnlyFocusesAPromptAndTurnsThatsItIntoTheDashboard() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        tick(model, at: "09:15")
        model.shortcut(.openDashboard)
        #expect(presenter.calls.last == "focus")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
        model.log(.existing(writing))

        clock.now = Fixture.at("12:00")
        model.doneForToday()
        model.shortcut(.openDashboard)
        if case .doneForToday = model.panel {} else { Issue.record("expected That's it for today") }
        #expect(presenter.calls.last == "show(focus: true)")
        model.shortcut(.openDashboard)
        #expect(shownDay(model)?.period == today)
        #expect(presenter.calls.last == "focus")
    }

    // MARK: Split

    /// Writing from 09:00, the check-in at 09:15 dismissed, the one at 09:30 covers half an hour.
    private func longSpan(_ model: AppModel) throws -> Int64 {
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        tick(model, at: "09:15")
        model.close()
        tick(model, at: "09:30")
        return writing
    }

    @Test func aSpanLongerThanAnIntervalCanBeSplit() throws {
        let model = try makeModel()
        let writing = try longSpan(model)
        #expect(
            model.panel
                == .checkIn(
                    CheckIn(mode: .timed, span: Fixture.span("09:00", "09:30"), prefill: writing, canSplit: true))
        )
    }

    @Test func aSplitBooksEveryPartAndTheLastOneRunsOn() throws {
        let model = try makeModel()
        let reading = try model.database.createActivity(name: "Reading").id!
        let writing = try longSpan(model)
        var offsite = CheckInList(catalog: model.catalog, prefill: nil)
        offsite.setText("Offsite")
        var split = SplitDraft(
            span: Fixture.span("09:00", "09:30"), first: CheckInList(catalog: model.catalog, prefill: writing),
            second: CheckInList(catalog: model.catalog, prefill: reading))
        split.addPart(offsite)
        model.log(split)
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        tick(model, at: "09:32")
        #expect(try timeline(model) == ["Writing 09:00-09:15", "Reading 09:15-09:22", "Offsite 09:22-09:32"])
    }

    @Test func aSplitEndingInBreakStartsTheBreak() throws {
        let model = try makeModel()
        let writing = try longSpan(model)
        var pause = CheckInList(catalog: model.catalog, prefill: nil)
        pause.setText("Break")
        model.log(
            SplitDraft(
                span: Fixture.span("09:00", "09:30"), first: CheckInList(catalog: model.catalog, prefill: writing),
                second: pause))
        #expect(model.mode == .onBreak)
        #expect(model.nowRow == .onBreak)
        tick(model, at: "09:45")
        #expect(model.panel == nil)
        #expect(try timeline(model) == ["Writing 09:00-09:15", "Break 09:15-09:45"])
    }

    @Test func returnWithAnEmptySplitPartSignalsAndKeepsTheSplit() throws {
        let model = try makeModel()
        let writing = try longSpan(model)
        let shown = model.panel
        model.log(
            SplitDraft(
                span: Fixture.span("09:00", "09:30"), first: CheckInList(catalog: model.catalog, prefill: writing),
                second: CheckInList(catalog: model.catalog, prefill: nil)))
        #expect(presenter.failures == 1)
        #expect(model.panel == shown)
        #expect(model.tracker.state.checkInShown)
    }

    @Test func aNewNameInTwoPartsCreatesOneActivity() throws {
        let model = try makeModel()
        let writing = try longSpan(model)
        var offsite = CheckInList(catalog: model.catalog, prefill: nil)
        offsite.setText("Offsite")
        var split = SplitDraft(
            span: Fixture.span("09:00", "09:30"), first: offsite,
            second: CheckInList(catalog: model.catalog, prefill: writing))
        offsite.setText("offsite")
        split.addPart(offsite)
        model.log(split)
        #expect(try model.database.activities().filter { $0.name.lowercased() == "offsite" }.count == 1)
        #expect(try timeline(model) == ["Offsite 09:00-09:15", "Writing 09:15-09:22", "Offsite 09:22-09:30"])
    }

    // MARK: Ignored actions and failures

    @Test func breakOnACheckInOpenedWhileOffKeepsItAndSignals() throws {
        let model = try makeModel()
        _ = try writingFrom0900(model)
        clock.now = Fixture.at("09:10")
        model.turnOff(for: nil)
        model.shortcut(.openCheckIn)
        let shown = model.panel
        model.startBreak()
        #expect(model.panel == shown)
        #expect(presenter.isVisible)
        #expect(presenter.failures == 1)
        #expect(model.mode == .off)
    }

    @Test func aSwitchBeforeTheTrackerNoticesTheReturnKeepsTheCheckInAndSignals() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        let reading = try model.database.createActivity(name: "Reading").id!
        clock.now = Fixture.at("09:05")
        model.send(.systemAway(since: Fixture.at("09:05")))
        clock.now = Fixture.at("09:40")
        model.shortcut(.openCheckIn)
        let shown = model.panel
        model.log(.existing(reading))
        #expect(model.panel == shown)
        #expect(presenter.isVisible)
        #expect(presenter.failures == 1)
        #expect(model.currentActivity == writing)
        tick(model, at: "09:41")
        #expect(model.panel == .awayReturn(span: Fixture.span("09:05", "09:41"), prefill: model.builtIns.breakId))
    }

    @Test func aFailedBookingSignals() throws {
        let model = try makeModel()
        model.apply([
            .book(
                Block(activityId: 9999, startedAt: Fixture.at("09:00"), endedAt: Fixture.at("09:10"), source: .checkIn))
        ])
        #expect(presenter.failures == 1)
        #expect(try timeline(model).isEmpty)
    }

    @Test func aFailedActivityCreationKeepsTheCheckInAndSignals() throws {
        let model = try makeModel()
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        let shown = model.panel
        model.log(.create(name: "Kickoff", projectId: 9999))
        #expect(presenter.failures == 1)
        #expect(model.panel == shown)
        #expect(presenter.isVisible)
        #expect(try model.database.activities().allSatisfy { $0.name != "Kickoff" })
    }

    // MARK: Returns

    /// Writing from 09:00, away from 09:05 (screen locked) until an input at 09:50.
    private func backFromAway(_ model: AppModel) throws -> Int64 {
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        clock.now = Fixture.at("09:05")
        model.send(.systemAway(since: Fixture.at("09:05")))
        tick(model, at: "09:50")
        return writing
    }

    @Test func backFromAwayAsksWithoutFocusPrefilledWithBreak() throws {
        let model = try makeModel()
        _ = try backFromAway(model)
        #expect(presenter.calls.last == "show(focus: false)")
        #expect(model.panel == .awayReturn(span: Fixture.span("09:05", "09:50"), prefill: model.builtIns.breakId))
    }

    @Test func awayAnsweredWithBreakBooksABreakAndWritingRunsOn() throws {
        let model = try makeModel()
        _ = try backFromAway(model)
        model.log(.existing(model.builtIns.breakId))
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        tick(model, at: "09:52")
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Break 09:05-09:50", "Writing 09:50-09:52"])
    }

    @Test func awayAnsweredWithPrivateBooksPrivateAndWritingRunsOn() throws {
        let model = try makeModel()
        _ = try backFromAway(model)
        model.log(.existing(model.builtIns.privateId))
        tick(model, at: "09:52")
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Private 09:05-09:50", "Writing 09:50-09:52"])
        #expect(model.tracker.mode == .tracking)
    }

    @Test func awayAnsweredWithAnActivityBooksItAndItRunsOn() throws {
        let model = try makeModel()
        _ = try backFromAway(model)
        let meeting = try model.database.createActivity(name: "Meeting").id!
        model.log(.existing(meeting))
        tick(model, at: "09:52")
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Meeting 09:05-09:52"])
    }

    @Test func awayAnsweredWithANewNameCreatesThatActivity() throws {
        let model = try makeModel()
        _ = try backFromAway(model)
        model.log(.create(name: "Offsite", projectId: nil))
        tick(model, at: "09:52")
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Offsite 09:05-09:52"])
    }

    @Test func dismissingTheAwayReturnCountsAsBreak() throws {
        let model = try makeModel()
        _ = try backFromAway(model)
        model.close()
        #expect(model.panel == nil)
        tick(model, at: "09:52")
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Break 09:05-09:50", "Writing 09:50-09:52"])
    }

    @Test func timedCheckInsResumeAfterTheAwayAnswer() throws {
        let model = try makeModel()
        let writing = try backFromAway(model)
        model.log(.existing(model.builtIns.breakId))
        tick(model, at: "10:05")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:50", "10:05"), prefill: writing)))
        #expect(presenter.calls.last == "show(focus: false)")
    }

    /// Writing from 09:00, a break from 09:05, away during it from 09:10 until an input at 09:40.
    private func backFromBreak(_ model: AppModel) throws -> Int64 {
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        clock.now = Fixture.at("09:05")
        model.startBreak()
        clock.now = Fixture.at("09:10")
        model.send(.systemAway(since: Fixture.at("09:10")))
        tick(model, at: "09:40")
        return writing
    }

    @Test func backFromABreakAsksWithoutFocusPrefilledWithTheActivityBefore() throws {
        let model = try makeModel()
        let writing = try backFromBreak(model)
        #expect(presenter.calls.last == "show(focus: false)")
        #expect(model.panel == .breakReturn(span: Fixture.span("09:05", "09:40"), prefill: writing))
    }

    @Test func theBreakReturnAnswerEndsTheBreakAndCheckInsResume() throws {
        let model = try makeModel()
        _ = try backFromBreak(model)
        let reading = try model.database.createActivity(name: "Reading").id!
        model.log(.existing(reading))
        #expect(model.panel == nil)
        #expect(model.tracker.mode == .tracking)
        tick(model, at: "09:55")
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Break 09:05-09:40", "Reading 09:40-09:55"])
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:40", "09:55"), prefill: reading)))
    }

    @Test func stillOnBreakAndEscapeKeepTheBreak() throws {
        let model = try makeModel()
        _ = try backFromBreak(model)
        model.close()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(model.tracker.mode == .onBreak)
        tick(model, at: "09:42")
        #expect(model.panel == nil)
        #expect(try timeline(model) == ["Writing 09:00-09:05", "Break 09:05-09:42"])
    }

    @Test func aNewNameCreatesTheActivity() throws {
        let model = try makeModel()
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.create(name: "Kickoff", projectId: nil))

        let kickoff = try #require(try model.database.activities().first { $0.name == "Kickoff" })
        #expect(kickoff.projectId == nil)
        #expect(model.tracker.currentActivity == kickoff.id)
        #expect(model.catalog.activity(kickoff.id) == kickoff)
    }

    @Test func aNewNameCreatesTheActivityWithItsProject() throws {
        let model = try makeModel()
        let acme = try model.database.createCustomer(name: "Acme")
        tick(model, at: "09:00")
        let relaunch = try model.createProject(name: "Relaunch", customerName: " acme ")
        #expect(relaunch.customerId == acme.id)
        model.shortcut(.openCheckIn)
        model.log(.create(name: "Kickoff", projectId: relaunch.id))

        let kickoff = try #require(try model.database.activities().first { $0.name == "Kickoff" })
        #expect(kickoff.projectId == relaunch.id)
        #expect(model.tracker.currentActivity == kickoff.id)
        #expect(model.catalog.activity(kickoff.id) == kickoff)
        #expect(model.catalog.projects.map(\.name) == ["Relaunch"])
    }

    @Test func aNewProjectTakesANewCustomerOrNone() throws {
        let model = try makeModel()
        let shop = try model.createProject(name: "Shop", customerName: "Northwind")
        let northwind = try #require(try model.database.customers().first)
        #expect(northwind.name == "Northwind")
        #expect(shop.customerId == northwind.id)
        #expect(try model.createProject(name: "Tools", customerName: "  ").customerId == nil)
        #expect(throws: WamaduError.emptyName) { try model.createProject(name: " ", customerName: "Globex") }
        #expect(try model.database.customers().map(\.name) == ["Northwind"])
        #expect(model.catalog.customers.map(\.name) == ["Northwind"])
    }

    @Test func trackerStateSurvivesARelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appending(path: "tracker-state.json")
        let database = try AppDatabase.inMemory()
        let model = try makeModel(database, stateURL: stateURL)
        let writing = try database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))

        let relaunched = try makeModel(database, stateURL: stateURL)
        #expect(relaunched.tracker.state == model.tracker.state)
        #expect(relaunched.tracker.currentActivity == writing)
    }

    @Test func anUnreadableStateStartsFresh() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appending(path: "tracker-state.json")
        try Data("not json".utf8).write(to: stateURL)
        #expect(try makeModel(stateURL: stateURL).tracker.state == TrackerState())
    }
}
