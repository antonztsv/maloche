import Foundation
import Testing

@testable import WamaduCore

@Suite struct TrackerAwayTests {
    /// The day started at 08:00 with Writing, the user works until `time`.
    private func working(until time: String = "10:00", current: Int64? = Fixture.writing) -> Harness {
        var h = Harness(current: current, settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: time)
        return h
    }

    /// Away from 10:00 by idling, back at 10:40.
    private func backFromAway() -> Harness {
        var h = working()
        h.pass(to: "10:39", idle: true)
        h.pass(to: "10:40")
        return h
    }

    private let awayPrompt = TrackerEffect.showAwayReturn(
        span: Fixture.span("10:00", "10:40"), prefill: Fixture.breakId)

    @Test func idleAtTheThresholdMakesTheUserAwayFromTheLastInput() {
        var h = working()
        h.pass(to: "10:20", idle: true)
        #expect(h.timeline == ["Writing 08:00-10:00"])
        #expect(h.prompts.isEmpty)
        h.pass(to: "10:39", idle: true)
        h.pass(to: "10:40")
        #expect(h.takePrompts() == [awayPrompt])
        #expect(h.timeline == ["Writing 08:00-10:00"])
    }

    @Test func previousActivityRunsProvisionallyFromTheReturnUntilTheAnswer() {
        var h = backFromAway()
        h.pass(to: "10:45")
        #expect(h.timeline == ["Writing 08:00-10:00", "Writing 10:40-10:45"])
    }

    @Test func dismissedAwayCountsAsBreak() {
        var h = backFromAway()
        h.pass(to: "10:45")
        h.send(.awayDismissed)
        #expect(h.timeline == ["Writing 08:00-10:00", "Break 10:00-10:40", "Writing 10:40-10:45"])
        #expect(h.blocks[1].source == .away)
        #expect(h.tracker.mode == .tracking)
    }

    @Test func privateAnswerBooksPrivateAndThePreviousActivityContinues() {
        var h = backFromAway()
        h.send(.awayAnswered(.private))
        h.pass(to: "10:50")
        #expect(h.timeline == ["Writing 08:00-10:00", "Private 10:00-10:40", "Writing 10:40-10:50"])
    }

    @Test func activityAnswerBooksTheAbsenceAndBecomesCurrent() {
        var h = backFromAway()
        h.pass(to: "10:45")
        h.send(.awayAnswered(.activity(Fixture.meeting)))
        h.pass(to: "10:50")
        #expect(h.timeline == ["Writing 08:00-10:00", "Meeting 10:00-10:40", "Meeting 10:40-10:50"])
    }

    @Test func lockMakesTheUserAwayFromTheLastInputBelowTheThreshold() {
        var h = working()
        h.pass(to: "10:05", idle: true)
        h.record(.systemAway(since: Fixture.at("10:00")))
        h.pass(to: "10:09", idle: true)
        #expect(h.prompts.isEmpty)
        h.pass(to: "10:10")
        #expect(h.takePrompts() == [.showAwayReturn(span: Fixture.span("10:00", "10:10"), prefill: Fixture.breakId)])
        #expect(h.timeline == ["Writing 08:00-10:00"])
    }

    @Test func systemTimesInTheFutureAreNotBooked() {
        var h = working()
        h.record(.tick(idleSeconds: -60))
        h.record(.systemAway(since: Fixture.at("10:30")))
        #expect(h.timeline == ["Writing 08:00-10:00"])
    }

    @Test func tickGapCountsAsAwayFromTheLastInputBeforeTheGap() {
        var h = working()
        h.now = Fixture.at("11:00")
        h.lastInput = h.now
        h.tick()
        #expect(h.takePrompts() == [.showAwayReturn(span: Fixture.span("10:00", "11:00"), prefill: Fixture.breakId)])
        #expect(h.timeline == ["Writing 08:00-10:00"])
    }

    @Test func tickGapBelowTheThresholdIsNotAway() {
        var h = working()
        h.now = Fixture.at("10:10")
        h.lastInput = h.now
        h.tick()
        #expect(h.prompts.isEmpty)
        #expect(h.timeline == ["Writing 08:00-10:10"])
    }

    @Test func appLaunchUsesThePersistedStateForTheGap() throws {
        var h = working()
        h.now = Fixture.at("11:00")
        h.lastInput = h.now
        try h.relaunch()
        h.tick()
        #expect(h.takePrompts() == [.showAwayReturn(span: Fixture.span("10:00", "11:00"), prefill: Fixture.breakId)])
    }

    @Test func appLaunchShowsAPendingAwayQuestionAgain() throws {
        var h = backFromAway()
        _ = h.takePrompts()
        h.pass(to: "10:42")
        try h.relaunch()
        #expect(h.takePrompts() == [awayPrompt])
    }

    @Test func awayAgainBeforeAnsweringSettlesThePendingAbsenceAsBreak() {
        var h = backFromAway()
        h.pass(to: "10:50")
        h.pass(to: "11:05", idle: true)
        #expect(h.takePrompts() == [awayPrompt, .hidePrompt])
        #expect(h.timeline == ["Writing 08:00-10:00", "Break 10:00-10:40", "Writing 10:40-10:50"])
        h.pass(to: "11:19", idle: true)
        h.pass(to: "11:20")
        #expect(h.takePrompts() == [.showAwayReturn(span: Fixture.span("10:50", "11:20"), prefill: Fixture.breakId)])
    }

    @Test func withoutPrefillTheTimeBeforeAnAbsenceGoesToTheFirstNamedActivity() {
        var h = working(current: nil)
        h.pass(to: "10:39", idle: true)
        h.pass(to: "10:40")
        h.send(.awayAnswered(.break))
        h.pass(to: "10:50")
        #expect(h.timeline == ["Break 10:00-10:40"])
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Reading 08:00-10:00", "Break 10:00-10:40", "Reading 10:40-10:50"])
    }

    @Test func breakBooksTheActivityUpToNowAndAsksOnReturn() {
        var h = working(until: "12:00")
        h.send(.startBreak)
        #expect(h.tracker.mode == .onBreak)
        #expect(h.timeline == ["Writing 08:00-12:00"])
        h.pass(to: "12:39", idle: true)
        #expect(h.prompts.isEmpty)
        h.pass(to: "12:40")
        #expect(
            h.takePrompts() == [.showBreakReturn(span: Fixture.span("12:00", "12:40"), prefill: Fixture.writing)])
        h.pass(to: "12:42")
        h.send(.breakReturnAnswered(Fixture.reading))
        h.pass(to: "12:50")
        #expect(h.timeline == ["Writing 08:00-12:00", "Break 12:00-12:40", "Reading 12:40-12:50"])
        #expect(h.tracker.mode == .tracking)
    }

    @Test func lockAndTickGapsDuringABreakAreNotAway() {
        var h = working(until: "12:00")
        h.send(.startBreak)
        h.pass(to: "12:01", idle: true)
        h.record(.systemAway(since: Fixture.at("12:00")))
        h.now = Fixture.at("12:30")
        h.lastInput = h.now
        h.tick()
        #expect(h.takePrompts() == [.showBreakReturn(span: Fixture.span("12:00", "12:30"), prefill: Fixture.writing)])
        #expect(h.timeline == ["Writing 08:00-12:00", "Break 12:00-12:30"])
    }

    @Test func shortBreakAsksWhenTheIconIsClicked() {
        var h = working(until: "12:00")
        h.send(.startBreak)
        h.pass(to: "12:10", idle: true)
        h.pass(to: "12:20")
        #expect(h.prompts.isEmpty)
        h.send(.openedDuringBreak)
        #expect(h.takePrompts() == [.showBreakReturn(span: Fixture.span("12:00", "12:20"), prefill: Fixture.writing)])
    }

    @Test func stillOnBreakKeepsTheBreakRunning() {
        var h = working(until: "12:00")
        h.send(.startBreak)
        h.pass(to: "12:39", idle: true)
        h.pass(to: "12:40")
        h.send(.stillOnBreak)
        #expect(h.tracker.mode == .onBreak)
        h.pass(to: "13:00")
        h.send(.openedDuringBreak)
        #expect(
            h.takePrompts() == [
                .showBreakReturn(span: Fixture.span("12:00", "12:40"), prefill: Fixture.writing),
                .showBreakReturn(span: Fixture.span("12:00", "13:00"), prefill: Fixture.writing),
            ])
        h.send(.breakReturnAnswered(Fixture.writing))
        h.pass(to: "13:10")
        #expect(h.timeline == ["Writing 08:00-12:00", "Break 12:00-13:00", "Writing 13:00-13:10"])
    }

    @Test func lockBeforeAnsweringSettlesThePendingAbsenceAsBreak() {
        var h = backFromAway()
        h.pass(to: "10:50")
        h.record(.systemAway(since: Fixture.at("10:50")))
        #expect(h.takePrompts() == [awayPrompt, .hidePrompt])
        #expect(h.timeline == ["Writing 08:00-10:00", "Break 10:00-10:40", "Writing 10:40-10:50"])
        h.pass(to: "10:59", idle: true)
        h.pass(to: "11:00")
        #expect(h.takePrompts() == [.showAwayReturn(span: Fixture.span("10:50", "11:00"), prefill: Fixture.breakId)])
    }

    /// Back from a break at 12:40, the break return stays unanswered.
    private func breakReturnPending() -> Harness {
        var h = working(until: "12:00")
        h.send(.startBreak)
        h.pass(to: "12:39", idle: true)
        h.pass(to: "12:40")
        return h
    }

    private let breakReturnPrompt = TrackerEffect.showBreakReturn(
        span: Fixture.span("12:00", "12:40"), prefill: Fixture.writing)

    @Test func awayDuringAPendingBreakReturnEndsTheBreakAtTheReturn() {
        var h = breakReturnPending()
        h.pass(to: "13:00")
        h.pass(to: "14:59", idle: true)
        h.pass(to: "15:00")
        #expect(
            h.takePrompts() == [
                breakReturnPrompt, .hidePrompt,
                .showAwayReturn(span: Fixture.span("13:00", "15:00"), prefill: Fixture.breakId),
            ])
        #expect(h.timeline == ["Writing 08:00-12:00", "Break 12:00-12:40", "Writing 12:40-13:00"])
        h.send(.breakReturnAnswered(Fixture.writing))
        h.send(.awayAnswered(.break))
        #expect(
            h.timeline == ["Writing 08:00-12:00", "Break 12:00-12:40", "Writing 12:40-13:00", "Break 13:00-15:00"])
    }

    @Test(arguments: [false, true])
    func lockOrSleepDuringAPendingBreakReturnIsAway(asleep: Bool) {
        var h = breakReturnPending()
        h.pass(to: "12:50")
        if asleep {
            h.now = Fixture.at("13:10")
            h.lastInput = h.now
            h.tick()
        } else {
            h.record(.systemAway(since: Fixture.at("12:50")))
            h.pass(to: "13:09", idle: true)
            h.pass(to: "13:10")
        }
        #expect(
            h.takePrompts() == [
                breakReturnPrompt, .hidePrompt,
                .showAwayReturn(span: Fixture.span("12:50", "13:10"), prefill: Fixture.breakId),
            ])
        #expect(h.timeline == ["Writing 08:00-12:00", "Break 12:00-12:40", "Writing 12:40-12:50"])
    }

    @Test func iconClickDuringAPendingBreakReturnShowsItAgain() {
        var h = breakReturnPending()
        h.pass(to: "12:45")
        h.send(.openedDuringBreak)
        #expect(h.takePrompts() == [breakReturnPrompt, breakReturnPrompt])
    }

    /// Escape on the break return sends `stillOnBreak`.
    @Test func escapeOnTheBreakReturnKeepsTheBreakAndTheNextReturnAsksAgain() {
        var h = breakReturnPending()
        h.send(.stillOnBreak)
        h.pass(to: "12:45")
        #expect(h.tracker.mode == .onBreak)
        #expect(h.timeline == ["Writing 08:00-12:00", "Break 12:00-12:45"])
        h.pass(to: "13:04", idle: true)
        h.pass(to: "13:05")
        #expect(
            h.takePrompts() == [
                breakReturnPrompt, .showBreakReturn(span: Fixture.span("12:00", "13:05"), prefill: Fixture.writing),
            ])
    }

    @Test(arguments: [TrackerEvent.checkInAnswered(Fixture.breakId), .switchActivity(Fixture.breakId)])
    func choosingBreakStartsABreak(event: TrackerEvent) {
        var h = working(until: "12:00")
        h.send(event)
        #expect(h.tracker.mode == .onBreak)
        h.pass(to: "12:39", idle: true)
        h.pass(to: "12:40")
        #expect(h.takePrompts() == [breakReturnPrompt])
        #expect(h.timeline == ["Writing 08:00-12:00", "Break 12:00-12:40"])
    }

    @Test func breakChosenInAReturnPromptIsNotRunAsAnActivity() {
        var h = breakReturnPending()
        h.send(.breakReturnAnswered(Fixture.breakId))
        #expect(h.tracker.mode == .onBreak)
        var away = backFromAway()
        away.send(.awayAnswered(.activity(Fixture.breakId)))
        away.pass(to: "10:50")
        #expect(away.timeline == ["Writing 08:00-10:00", "Break 10:00-10:40", "Writing 10:40-10:50"])
    }

    @Test func lockShorterThanTheThresholdEndsTheBreakWithTheNextInput() {
        var h = working(until: "12:00")
        h.send(.startBreak)
        h.pass(to: "12:01")
        h.record(.systemAway(since: Fixture.at("12:01")))
        h.pass(to: "12:10", idle: true)
        #expect(h.prompts.isEmpty)
        h.pass(to: "12:11")
        #expect(h.takePrompts() == [.showBreakReturn(span: Fixture.span("12:00", "12:11"), prefill: Fixture.writing)])
    }
}
