import Foundation
import Testing

@testable import WamaduCore

@Suite struct TrackerScheduleTests {
    private let sundayPlan = TrackerSettings(
        checkInInterval: Fixture.noCheckIns.checkInInterval,
        schedule: WorkSchedule(plans: [1: .init(start: 8 * 60, end: 18 * 60)]))

    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test func standardPlanIsMondayToFridayFromEightToSix() {
        let schedule = WorkSchedule.standard
        #expect(schedule.interval(on: Fixture.at("12:00"), calendar: Fixture.berlin) == Fixture.span("08:00", "18:00"))
        #expect(
            schedule.interval(on: Fixture.at("2026-11-13 07:00"), calendar: Fixture.berlin)
                == Fixture.span("2026-11-13 08:00", "2026-11-13 18:00"))
        #expect(schedule.interval(on: Fixture.at("2026-11-14 12:00"), calendar: Fixture.berlin) == nil)
        #expect(schedule.interval(on: Fixture.at("2026-11-15 12:00"), calendar: Fixture.berlin) == nil)
    }

    @Test(arguments: [("2026-03-29", "06:00", "16:00"), ("2026-10-25", "07:00", "17:00")])
    func planKeepsWallClockTimesOnDaylightSavingDays(day: String, startUTC: String, endUTC: String) {
        let interval = sundayPlan.schedule.interval(on: Fixture.at("\(day) 12:00"), calendar: Fixture.berlin)
        #expect(interval == DateInterval(start: utc("\(day)T\(startUTC):00Z"), end: utc("\(day)T\(endUTC):00Z")))
    }

    @Test(arguments: ["2026-03-29", "2026-10-25"])
    func trackingFollowsThePlanOnDaylightSavingDays(day: String) {
        let date = String(day.suffix(5))
        var h = Harness(at: "\(day) 07:58", settings: sundayPlan)
        h.tick()
        h.pass(to: "\(day) 08:02")
        #expect(h.timeline == ["Writing \(date) 08:00-\(date) 08:02"])
        var evening = Harness(at: "\(day) 17:55", settings: sundayPlan)
        evening.tick()
        evening.pass(to: "\(day) 18:05")
        #expect(evening.timeline == ["Writing \(date) 17:55-\(date) 18:00"])
    }

    @Test func dayStartsWithTheFirstInputInsideThePlan() {
        var h = Harness(at: "07:30", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "07:55")
        h.pass(to: "08:05", idle: true)
        #expect(h.tracker.mode == .off)
        h.pass(to: "08:06")
        h.pass(to: "08:10")
        #expect(h.timeline == ["Writing 08:06-08:10"])
        #expect(h.tracker.mode == .tracking)
    }

    @Test func planEndBooksUpToTheEndAndStops() {
        var h = Harness(at: "17:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "18:30")
        #expect(h.timeline == ["Writing 17:00-18:00"])
        #expect(h.tracker.mode == .off)
    }

    @Test func planEndBooksUpToTheLastInputWhenIdle() {
        var h = Harness(at: "17:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "17:50")
        h.pass(to: "18:30", idle: true)
        h.pass(to: "18:40")
        #expect(h.timeline == ["Writing 17:00-17:50"])
        #expect(h.prompts.isEmpty)
    }

    @Test func awayAcrossThePlanEndEndsTheDayAtTheStartOfTheAbsence() {
        var h = Harness(at: "17:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "17:30")
        h.pass(to: "18:30", idle: true)
        h.pass(to: "19:00")
        #expect(h.timeline == ["Writing 17:00-17:30"])
        h.now = Fixture.at("2026-11-10 08:00")
        h.lastInput = h.now
        h.tick()
        h.pass(to: "2026-11-10 08:05")
        #expect(h.prompts.isEmpty)
        #expect(h.tracker.mode == .tracking)
        #expect(h.timeline == ["Writing 17:00-17:30"])
    }

    @Test func sleepAcrossThePlanEndDoesNotAskTheNextMorning() {
        var h = Harness(at: "17:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "17:30")
        h.record(.systemAway(since: Fixture.at("17:30")))
        h.now = Fixture.at("2026-11-10 08:05")
        h.lastInput = h.now
        h.tick()
        h.pass(to: "2026-11-10 08:10")
        #expect(h.prompts.isEmpty)
        #expect(h.tracker.mode == .tracking)
        #expect(h.timeline == ["Writing 17:00-17:30"])
    }

    @Test func breakAcrossThePlanEndEndsTheDayAtTheLastInput() {
        var h = Harness(at: "17:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "17:30")
        h.send(.startBreak)
        h.pass(to: "17:35")
        h.now = Fixture.at("2026-11-10 08:05")
        h.lastInput = h.now
        h.tick()
        h.pass(to: "2026-11-10 08:10")
        #expect(h.prompts.isEmpty)
        #expect(h.tracker.mode == .tracking)
        #expect(h.timeline == ["Writing 17:00-17:30", "Break 17:30-17:35"])
    }

    /// Back from a break at 12:30, the break return stays unanswered.
    private func breakReturnPending() -> Harness {
        var h = Harness(at: "11:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "12:00")
        h.send(.startBreak)
        h.pass(to: "12:29", idle: true)
        h.pass(to: "12:30")
        #expect(h.takePrompts() == [.showBreakReturn(span: Fixture.span("12:00", "12:30"), prefill: Fixture.writing)])
        return h
    }

    @Test func planEndDuringAPendingBreakReturnEndsTheBreakAtTheReturn() {
        var h = breakReturnPending()
        h.pass(to: "18:30")
        #expect(h.takePrompts() == [.hidePrompt])
        #expect(h.timeline == ["Writing 11:00-12:00", "Break 12:00-12:30", "Writing 12:30-18:00"])
        #expect(h.tracker.mode == .off)
    }

    @Test func doneDuringAPendingBreakReturnEndsTheBreakAtTheReturn() {
        var h = breakReturnPending()
        h.pass(to: "13:00")
        h.send(.doneForToday)
        #expect(h.takePrompts() == [.hidePrompt])
        #expect(h.timeline == ["Writing 11:00-12:00", "Break 12:00-12:30", "Writing 12:30-13:00"])
    }

    @Test(arguments: [
        TrackerEvent.startBreak, .checkInAnswered(Fixture.reading), .checkInDismissed, .stopContinuing,
        .checkInSplit(dividers: [Fixture.at("10:10")], activities: [Fixture.reading, Fixture.meeting]),
        .awayAnswered(.break), .breakReturnAnswered(Fixture.reading), .openedDuringBreak, .stillOnBreak,
    ])
    func userActionsWhileOffOnlyCountAsInput(event: TrackerEvent) {
        var h = Harness(at: "10:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "10:20")
        h.send(.turnOff(for: nil))
        h.pass(to: "10:30")
        var before = h.tracker.state
        let bookings = h.bookings
        h.send(event)
        before.lastInput = h.now
        #expect(h.tracker.state == before)
        #expect(h.bookings == bookings)
        #expect(h.prompts.isEmpty)
    }

    @Test func doneForTodayStopsUntilTheNextDay() {
        var h = Harness(at: "14:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "15:00")
        h.send(.doneForToday)
        #expect(h.tracker.mode == .off)
        h.pass(to: "16:00")
        #expect(h.timeline == ["Writing 14:00-15:00"])
        h.now = Fixture.at("2026-11-10 08:00")
        h.lastInput = h.now
        h.tick()
        h.pass(to: "2026-11-10 08:05")
        #expect(h.tracker.mode == .tracking)
        #expect(h.timeline == ["Writing 14:00-15:00"])
    }

    @Test func keepTrackingResumesAfterDone() {
        var h = Harness(at: "14:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "15:00")
        h.send(.doneForToday)
        h.pass(to: "15:10")
        h.send(.keepTracking)
        h.pass(to: "15:20")
        #expect(h.timeline == ["Writing 14:00-15:00", "Writing 15:10-15:20"])
    }

    @Test func turnOffForThirtyMinutesResumesWithThePreviousActivity() {
        var h = Harness(at: "10:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "10:20")
        h.send(.turnOff(for: 30 * 60))
        #expect(h.tracker.mode == .off)
        h.pass(to: "10:49")
        #expect(h.timeline == ["Writing 10:00-10:20"])
        h.pass(to: "11:00")
        #expect(h.timeline == ["Writing 10:00-10:20", "Writing 10:50-11:00"])
        #expect(h.tracker.mode == .tracking)
    }

    @Test func turnOffForTheSessionLastsUntilTurnOnOrRelaunch() throws {
        var h = Harness(at: "10:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "10:20")
        h.send(.turnOff(for: nil))
        h.pass(to: "12:00")
        #expect(h.tracker.mode == .off)
        h.send(.turnOn)
        h.pass(to: "12:10")
        h.send(.turnOff(for: nil))
        h.pass(to: "12:30")
        try h.relaunch()
        h.pass(to: "12:40")
        #expect(h.timeline == ["Writing 10:00-10:20", "Writing 12:00-12:10", "Writing 12:30-12:40"])
    }

    @Test func turnOnOutsideThePlanTracksUntilTheNextAbsence() {
        var h = Harness(at: "19:00", settings: Fixture.noCheckIns)
        h.tick()
        #expect(h.tracker.mode == .off)
        h.send(.turnOn)
        h.pass(to: "19:30")
        h.pass(to: "19:59", idle: true)
        h.pass(to: "20:10")
        #expect(h.prompts.isEmpty)
        #expect(h.tracker.mode == .off)
        #expect(h.timeline == ["Writing 19:00-19:30"])
    }

    @Test func turnOnBeforeThePlanAsksAfterAnAbsenceThatEndsInsideThePlan() {
        var h = Harness(at: "07:00", settings: Fixture.noCheckIns)
        h.tick()
        h.send(.turnOn)
        h.pass(to: "07:30")
        h.pass(to: "08:29", idle: true)
        h.pass(to: "08:30")
        #expect(h.takePrompts() == [.showAwayReturn(span: Fixture.span("07:30", "08:30"), prefill: Fixture.breakId)])
    }

    @Test func continueWithoutAskingIgnoresIdleUntilTheDurationEnds() {
        var h = Harness(at: "10:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "10:15")
        h.send(.continueWithoutAsking(Fixture.meeting, for: 60 * 60))
        #expect(h.tracker.mode == .continuing)
        h.pass(to: "11:15", idle: true)
        #expect(h.prompts.isEmpty)
        #expect(h.timeline == ["Writing 10:00-10:15", "Meeting 10:15-11:15"])
        #expect(h.blocks.last?.source == .continued)
        #expect(h.tracker.mode == .tracking)
        h.pass(to: "11:20")
        #expect(h.timeline == ["Writing 10:00-10:15", "Meeting 10:15-11:15", "Meeting 11:15-11:20"])
    }

    @Test func lockDuringContinueMakesTheUserAwayFromTheLock() {
        var h = Harness(at: "10:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "10:15")
        h.send(.continueWithoutAsking(Fixture.meeting, for: nil))
        h.pass(to: "10:45", idle: true)
        h.record(.systemAway(since: Fixture.at("10:15")))
        h.pass(to: "11:09", idle: true)
        h.pass(to: "11:10")
        #expect(h.takePrompts() == [.showAwayReturn(span: Fixture.span("10:45", "11:10"), prefill: Fixture.breakId)])
        #expect(h.timeline == ["Writing 10:00-10:15", "Meeting 10:15-10:45"])
        #expect(h.tracker.mode == .tracking)
    }

    @Test func stopContinuingResumesNormalTracking() {
        var h = Harness(at: "10:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "10:15")
        h.send(.continueWithoutAsking(Fixture.meeting, for: nil))
        h.pass(to: "10:30")
        h.send(.stopContinuing)
        h.pass(to: "10:40")
        #expect(h.timeline == ["Writing 10:00-10:15", "Meeting 10:15-10:30", "Meeting 10:30-10:40"])
        #expect(h.blocks.map(\.source) == [.checkIn, .continued, .checkIn])
    }

    @Test func runningBlockCrossesMidnightAndTheFirstAnswerIsPerTrackingDay() {
        var h = Harness(at: "23:00", settings: Fixture.noCheckIns)
        h.tick()
        h.send(.turnOn)
        h.pass(to: "23:30")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "2026-11-10 00:30")
        #expect(h.timeline == ["Writing 23:00-11-10 00:30"])
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Writing 23:00-11-10 00:00", "Reading 11-10 00:00-11-10 00:30"])
    }

    @Test func aRunTurnedOnTheEveningBeforeGoesOnIntoTheNextDaysPlan() {
        var h = Harness(at: "2026-11-08 23:30", settings: Fixture.noCheckIns)
        h.tick()
        h.send(.turnOn)
        h.pass(to: "08:10")
        #expect(h.timeline == ["Writing 11-08 23:30-08:10"])
        #expect(h.tracker.currentActivity == Fixture.writing)
    }

    @Test func doneForTodayIsPerCalendarDay() {
        var h = Harness(at: "23:00", settings: Fixture.noCheckIns)
        h.tick()
        h.send(.turnOn)
        h.pass(to: "23:30")
        h.send(.doneForToday)
        h.now = Fixture.at("2026-11-10 08:00")
        h.lastInput = h.now
        h.tick()
        #expect(h.tracker.mode == .tracking)
    }

    @Test func doneAfterMidnightEndsTheTrackingDay() {
        var h = Harness(at: "23:00", settings: Fixture.noCheckIns)
        h.tick()
        h.send(.turnOn)
        h.pass(to: "2026-11-10 00:30")
        h.send(.doneForToday)
        h.now = Fixture.at("2026-11-10 08:00")
        h.lastInput = h.now
        h.tick()
        h.pass(to: "2026-11-10 12:00")
        #expect(h.tracker.mode == .tracking)
        #expect(h.timeline.last == "Writing 23:00-11-10 00:30")
    }

    @Test func turnOnBeforeThePlanEndsWithThePlan() {
        var h = Harness(at: "07:50", settings: Fixture.noCheckIns)
        h.tick()
        h.send(.turnOn)
        h.pass(to: "19:00")
        #expect(h.timeline == ["Writing 07:50-18:00"])
        #expect(h.tracker.mode == .off)
    }

    @Test func keepTrackingAfterDoneLetsTrackingRestartLaterThatDay() {
        var h = Harness(at: "14:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "15:00")
        h.send(.doneForToday)
        h.pass(to: "15:10")
        h.send(.keepTracking)
        h.pass(to: "15:20")
        h.send(.turnOff(for: 30 * 60))
        h.now = Fixture.at("16:30")
        h.lastInput = h.now
        h.tick()
        h.pass(to: "16:40")
        #expect(h.timeline == ["Writing 14:00-15:00", "Writing 15:10-15:20", "Writing 16:30-16:40"])
    }

    @Test(arguments: [false, true])
    func turnOffForTheSessionSurvivesMidnightAndEndsWithARelaunch(asleep: Bool) throws {
        var h = Harness(at: "15:00", settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "15:10")
        h.send(.turnOff(for: nil))
        if asleep {
            h.now = Fixture.at("2026-11-10 08:04")
            h.tick()
        } else {
            h.pass(to: "2026-11-10 08:04", idle: true)
        }
        h.pass(to: "2026-11-10 08:10")
        #expect(h.tracker.mode == .off)
        #expect(h.timeline == ["Writing 15:00-15:10"])
        try h.relaunch()
        h.pass(to: "2026-11-10 08:20")
        #expect(h.tracker.mode == .tracking)
        #expect(h.timeline == ["Writing 15:00-15:10"])
    }

    @Test func stateSurvivesACodableRoundTrip() throws {
        var h = Harness(at: "19:00", settings: Fixture.noCheckIns)
        h.tick()
        h.send(.turnOn)
        h.pass(to: "19:10")
        h.send(.continueWithoutAsking(Fixture.meeting, for: 30 * 60))
        let state = h.tracker.state
        let decoded = try JSONDecoder().decode(TrackerState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        try h.relaunch()
        h.pass(to: "19:45", idle: true)
        #expect(h.timeline == ["Writing 19:00-19:10", "Meeting 19:10-19:40"])
    }
}
