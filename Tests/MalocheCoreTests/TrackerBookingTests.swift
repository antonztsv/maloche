import Foundation
import Testing

@testable import MalocheCore

@Suite struct TrackerBookingTests {
    /// `minutes` booked by the answer when absences lie in the span.
    private func checkIn(_ start: String, _ end: String, minutes: Int? = nil, canSplit: Bool = false) -> TrackerEffect {
        .showCheckIn(
            CheckInPrompt(
                span: Fixture.span(start, end), duration: minutes.map { TimeInterval($0 * 60) },
                prefill: Fixture.writing, canSplit: canSplit))
    }

    /// The day has no answer yet, away from 08:10 by idling, back at 08:30.
    private func backBeforeTheFirstAnswer() -> Harness {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:10")
        h.pass(to: "08:29", idle: true)
        h.pass(to: "08:30")
        return h
    }

    @Test func theActivityOfAnEarlierDayIsOnlyThePrefillAndNothingIsBookedBeforeTheFirstAnswer() {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:15")
        #expect(h.timeline.isEmpty)
        #expect(h.tracker.mode == .tracking)
        #expect(h.tracker.currentActivity == nil)
        #expect(h.tracker.prefill == Fixture.writing)
        #expect(h.takePrompts() == [checkIn("08:00", "08:15")])
    }

    @Test func aDismissedFirstCheckInBooksNothingAndTheDayStartsAgainAtTheDismissal() {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:16")
        h.send(.checkInDismissed)
        _ = h.takePrompts()
        h.pass(to: "08:31")
        #expect(h.timeline.isEmpty)
        #expect(h.takePrompts() == [checkIn("08:16", "08:31")])
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Reading 08:16-08:31"])
    }

    @Test func aDayWithoutAnAnswerBooksNothing() {
        var h = Harness(at: "16:00", answered: false)
        h.tick()
        h.pass(to: "17:00")
        h.send(.checkInDismissed)
        h.pass(to: "18:30")
        #expect(h.timeline.isEmpty)
        #expect(h.tracker.mode == .off)
        h.now = Fixture.at("2026-11-10 08:00")
        h.lastInput = h.now
        h.tick()
        h.pass(to: "2026-11-10 08:10")
        h.send(.switchActivity(Fixture.reading))
        #expect(h.timeline == ["Reading 11-10 08:00-11-10 08:10"])
    }

    /// Break or Private on the return confirm nothing, the first answer gets the day except the absence.
    @Test(arguments: [(AwayAnswer.break, "Break"), (.private, "Private")])
    func anAbsenceBeforeTheFirstAnswerGoesOnlyToTheAwayAnswer(answer: AwayAnswer, name: String) {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:10")
        h.pass(to: "08:29", idle: true)
        h.pass(to: "08:30")
        h.send(.awayAnswered(answer))
        h.pass(to: "08:40")
        #expect(h.timeline == ["\(name) 08:10-08:30"])
        #expect(h.tracker.currentActivity == nil)
        h.pass(to: "08:45")
        #expect(h.takePrompts().last == checkIn("08:00", "08:45", minutes: 25))
        h.send(.checkInAnswered(Fixture.reading))
        h.pass(to: "08:50")
        #expect(h.timeline == ["Reading 08:00-08:10", "\(name) 08:10-08:30", "Reading 08:30-08:50"])
    }

    /// The absence may have been a meeting, so the question shows; dismissed, it books nothing, also no Break.
    @Test func aDismissedReturnBeforeTheFirstAnswerBooksNothingAndTheAbsenceStaysFree() {
        var h = backBeforeTheFirstAnswer()
        #expect(h.takePrompts().last == .showAwayReturn(span: Fixture.span("08:10", "08:30"), prefill: Fixture.breakId))
        h.pass(to: "08:32")
        h.send(.awayDismissed)
        h.pass(to: "08:46")
        #expect(h.timeline.isEmpty)
        #expect(h.tracker.currentActivity == nil)
        h.pass(to: "08:47")
        #expect(h.takePrompts().last == checkIn("08:00", "08:47", minutes: 27))
        h.send(.checkInAnswered(Fixture.reading))
        h.pass(to: "08:50")
        #expect(h.timeline == ["Reading 08:00-08:10", "Reading 08:30-08:50"])
    }

    @Test func aReturnSettledByTheNextAbsenceBeforeTheFirstAnswerBooksNothing() {
        var h = backBeforeTheFirstAnswer()
        h.pass(to: "08:35")
        h.pass(to: "08:50", idle: true)
        #expect(
            h.takePrompts().suffix(2) == [
                .showAwayReturn(span: Fixture.span("08:10", "08:30"), prefill: Fixture.breakId), .hidePrompt,
            ])
        #expect(h.timeline.isEmpty)
        h.pass(to: "08:59", idle: true)
        h.pass(to: "09:00")
        h.send(.awayAnswered(.break))
        h.pass(to: "09:15")
        #expect(h.takePrompts().last == checkIn("08:00", "09:15", minutes: 30))
        h.send(.checkInAnswered(Fixture.reading))
        #expect(
            h.timeline == [
                "Reading 08:00-08:10", "Reading 08:30-08:35", "Break 08:35-09:00", "Reading 09:00-09:15",
            ])
    }

    /// A split of the time since 08:00 would book over the absence.
    @Test func noSplitBeforeTheFirstAnswerWhileAnAbsenceLiesInTheUnbookedTime() {
        var h = backBeforeTheFirstAnswer()
        h.send(.awayDismissed)
        h.pass(to: "09:00")
        #expect(h.takePrompts().last == checkIn("08:00", "09:00", minutes: 40))
        h.send(.checkInSplit(dividers: [Fixture.at("08:40")], activities: [Fixture.reading, Fixture.meeting]))
        #expect(h.timeline.isEmpty)
        h.send(.checkInAnswered(Fixture.meeting))
        #expect(h.timeline == ["Meeting 08:00-08:10", "Meeting 08:30-09:00"])
    }

    /// Away from the first input of the day, the unbooked time is one span from the return.
    @Test func aSplitBeforeTheFirstAnswerCoversTheUnbookedTimeFromTheReturn() {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:29", idle: true)
        h.pass(to: "08:32")
        h.send(.awayDismissed)
        h.pass(to: "08:47")
        #expect(h.takePrompts().last == checkIn("08:30", "08:47", canSplit: true))
        h.send(.checkInSplit(dividers: [Fixture.at("08:40")], activities: [Fixture.reading, Fixture.meeting]))
        #expect(h.timeline == ["Reading 08:30-08:40", "Meeting 08:40-08:47"])
    }

    @Test func anActivityOnTheReturnBeforeTheFirstAnswerIsTheFirstAnswer() {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:10")
        h.pass(to: "08:29", idle: true)
        h.pass(to: "08:30")
        h.send(.awayAnswered(.activity(Fixture.writing)))
        h.pass(to: "08:40")
        #expect(h.timeline == ["Writing 08:00-08:10", "Writing 08:10-08:30", "Writing 08:30-08:40"])
        #expect(h.tracker.currentActivity == Fixture.writing)
    }

    @Test func breakOnAReturnLaterInTheDayKeepsTheActivityAndTheNextAnswerSplits() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:10")
        h.pass(to: "08:29", idle: true)
        h.pass(to: "08:30")
        h.send(.awayAnswered(.break))
        h.pass(to: "08:45")
        h.send(.checkInAnswered(Fixture.reading))
        #expect(
            h.timeline == [
                "Writing 08:00-08:10", "Break 08:10-08:30", "Writing 08:30-08:37:30", "Reading 08:37:30-08:45",
            ])
    }

    @Test func aBreakBeforeTheFirstAnswerLeavesTheTimeBeforeItToTheAnswerOnReturn() {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:10")
        h.send(.startBreak)
        h.pass(to: "08:30")
        h.send(.openedDuringBreak)
        #expect(
            h.takePrompts().last == .showBreakReturn(span: Fixture.span("08:10", "08:30"), prefill: Fixture.writing))
        h.send(.breakReturnAnswered(Fixture.reading))
        h.pass(to: "08:40")
        #expect(h.timeline == ["Reading 08:00-08:10", "Break 08:10-08:30", "Reading 08:30-08:40"])
    }

    @Test func withoutPrefillNothingIsBookedUntilTheFirstAnswer() {
        var h = Harness(current: nil)
        h.tick()
        h.pass(to: "08:10")
        #expect(h.timeline.isEmpty)
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Reading 08:00-08:10"])
    }

    @Test func firstAnswerOfTheDayGetsTheWholeSpan() {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.reading))
        h.pass(to: "08:20")
        #expect(h.timeline == ["Reading 08:00-08:20"])
    }

    @Test func sameActivityGetsTheWholeSpan() {
        var h = Harness(answered: false)
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "08:30")
        h.send(.checkInAnswered(Fixture.writing))
        #expect(h.timeline == ["Writing 08:00-08:30"])
    }

    @Test func differentActivitySplitsTheSpanInTheMiddle() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "08:30:01")
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Writing 08:00-08:22:30", "Reading 08:22:30-08:30:01"])
        h.pass(to: "08:40:01")
        #expect(h.timeline == ["Writing 08:00-08:22:30", "Reading 08:22:30-08:40:01"])
    }

    @Test func manualSwitchBooksUpToNowAndRestartsTheSpan() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "08:20")
        h.send(.switchActivity(Fixture.reading))
        h.pass(to: "08:25")
        #expect(h.timeline == ["Writing 08:00-08:20", "Reading 08:20-08:25"])
        #expect(h.blocks.last?.source == .manual)
        h.pass(to: "08:40")
        h.send(.checkInAnswered(Fixture.meeting))
        #expect(h.timeline == ["Writing 08:00-08:20", "Reading 08:20-08:30", "Meeting 08:30-08:40"])
    }

    @Test func dismissedCheckInKeepsTheCurrentActivityRunning() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "08:30")
        h.send(.checkInDismissed)
        h.pass(to: "09:00")
        #expect(h.timeline == ["Writing 08:00-09:00"])
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Writing 08:00-08:37:30", "Reading 08:37:30-09:00"])
    }

    @Test func idleBelowTheThresholdIsFilledWhenTheUserIsActiveAgain() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:10")
        h.pass(to: "08:20", idle: true)
        #expect(h.timeline == ["Writing 08:00-08:10"])
        h.pass(to: "08:21")
        #expect(h.timeline == ["Writing 08:00-08:21"])
    }

    @Test func provisionalBookingHappensAtMostOncePerMinute() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:01")
        let before = h.bookings
        h.now = Fixture.at("08:01:30")
        h.lastInput = h.now
        h.tick()
        h.now = Fixture.at("08:01:59")
        h.lastInput = h.now
        h.tick()
        #expect(h.bookings == before)
        h.pass(to: "08:02")
        #expect(h.bookings == before + 1)
        #expect(h.timeline == ["Writing 08:00-08:02"])
    }

    @Test func emittedDatesAreTruncatedToWholeSeconds() {
        var h = Harness(answered: false)
        h.now += 0.7
        h.lastInput = h.now
        h.tick()
        h.now += 90.6
        h.lastInput = h.now - 0.2
        h.tick()
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Reading 08:00-08:01:31"])
    }

    @Test func modeIsOffBeforeTheDayStarts() {
        let h = Harness()
        #expect(h.tracker.mode == .off)
    }
}
