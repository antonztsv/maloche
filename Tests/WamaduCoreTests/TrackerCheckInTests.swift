import Foundation
import Testing

@testable import WamaduCore

@Suite struct TrackerCheckInTests {
    private func checkIn(
        _ start: String, _ end: String, prefill: Int64? = Fixture.writing, canSplit: Bool = false
    ) -> TrackerEffect {
        .showCheckIn(CheckInPrompt(span: Fixture.span(start, end), prefill: prefill, canSplit: canSplit))
    }

    private func started(at time: String = "08:00", current: Int64? = Fixture.writing) -> Harness {
        var h = Harness(at: time, current: current)
        h.tick()
        return h
    }

    @Test func firstCheckInIsDueOneIntervalAfterTheDayStarts() {
        var h = started()
        h.pass(to: "08:14")
        #expect(h.prompts.isEmpty)
        h.pass(to: "08:15")
        #expect(h.takePrompts() == [checkIn("08:00", "08:15")])
    }

    @Test func checkInWithoutPrefillBeforeAnyActivity() {
        var h = started(current: nil)
        h.pass(to: "08:15")
        #expect(h.takePrompts() == [checkIn("08:00", "08:15", prefill: nil)])
    }

    @Test func everyAnswerRestartsTheInterval() {
        var h = started()
        h.pass(to: "08:15")
        h.pass(to: "08:20")
        h.send(.checkInAnswered(Fixture.reading))
        _ = h.takePrompts()
        h.pass(to: "08:34")
        #expect(h.prompts.isEmpty)
        h.pass(to: "08:35")
        #expect(h.takePrompts() == [checkIn("08:20", "08:35", prefill: Fixture.reading)])
    }

    @Test func manualSwitchRestartsTheInterval() {
        var h = started()
        h.pass(to: "08:10")
        h.send(.switchActivity(Fixture.reading))
        h.pass(to: "08:24")
        #expect(h.prompts.isEmpty)
        h.pass(to: "08:25")
        #expect(h.takePrompts() == [checkIn("08:10", "08:25", prefill: Fixture.reading)])
    }

    @Test func dismissedCheckInIsFollowedByOneNamingTheWholeSpan() {
        var h = started()
        h.pass(to: "08:16")
        h.send(.checkInDismissed)
        _ = h.takePrompts()
        h.pass(to: "08:29")
        #expect(h.prompts.isEmpty)
        h.pass(to: "08:30")
        #expect(h.takePrompts() == [checkIn("08:00", "08:30", canSplit: true)])
    }

    @Test func visibleCheckInIsShownAgainWithTheUpdatedSpan() {
        var h = started()
        h.pass(to: "08:30")
        #expect(h.takePrompts() == [checkIn("08:00", "08:15"), checkIn("08:00", "08:30", canSplit: true)])
    }

    @Test func noCheckInDuringABreak() {
        var h = started()
        h.pass(to: "10:00")
        _ = h.takePrompts()
        h.send(.startBreak)
        #expect(h.takePrompts() == [.hidePrompt])
        h.pass(to: "11:00")
        #expect(h.prompts.isEmpty)
        h.send(.openedDuringBreak)
        h.send(.breakReturnAnswered(Fixture.writing))
        _ = h.takePrompts()
        h.pass(to: "11:15")
        #expect(h.takePrompts() == [checkIn("11:00", "11:15")])
    }

    @Test func noCheckInWhileAwayOrBeforeTheAwayAnswer() {
        var h = started()
        h.pass(to: "10:00")
        _ = h.takePrompts()
        h.pass(to: "10:39", idle: true)
        h.pass(to: "11:00")
        #expect(
            h.takePrompts() == [
                .hidePrompt, .showAwayReturn(span: Fixture.span("10:00", "10:40"), prefill: Fixture.breakId),
            ])
        h.send(.awayAnswered(.break))
        h.pass(to: "11:15")
        #expect(h.takePrompts() == [checkIn("11:00", "11:15")])
    }

    @Test func awayHidesAVisibleCheckIn() {
        var h = started()
        h.pass(to: "08:20")
        h.pass(to: "08:35", idle: true)
        #expect(
            h.takePrompts() == [checkIn("08:00", "08:15"), checkIn("08:00", "08:30", canSplit: true), .hidePrompt])
    }

    @Test func noCheckInWhileOffAndAFreshIntervalAfterwards() {
        var h = started(at: "10:00")
        h.pass(to: "10:05")
        h.send(.turnOff(for: 30 * 60))
        h.pass(to: "10:44")
        #expect(h.prompts.isEmpty)
        h.pass(to: "10:50")
        #expect(h.takePrompts() == [checkIn("10:35", "10:50")])
    }

    @Test func noCheckInWhileContinuingAndAFreshIntervalAfterwards() {
        var h = started(at: "10:00")
        h.pass(to: "10:05")
        h.send(.continueWithoutAsking(Fixture.meeting, for: 60 * 60))
        h.pass(to: "11:19")
        #expect(h.prompts.isEmpty)
        h.pass(to: "11:20")
        #expect(h.takePrompts() == [checkIn("11:05", "11:20", prefill: Fixture.meeting)])
    }

    @Test func noCheckInOutsideThePlanUnlessTurnedOn() {
        var h = started(at: "18:30")
        h.pass(to: "19:00")
        #expect(h.prompts.isEmpty)
        h.send(.turnOn)
        h.pass(to: "19:15")
        #expect(h.takePrompts() == [checkIn("19:00", "19:15")])
    }

    @Test func appLaunchShowsAVisibleCheckInAgain() throws {
        var h = started()
        h.pass(to: "08:20")
        _ = h.takePrompts()
        try h.relaunch()
        #expect(h.takePrompts() == [checkIn("08:00", "08:20", canSplit: true)])
    }
}
