import Foundation
import Testing

@testable import WamaduCore

@Suite struct TrackerBookingTests {
    @Test func prefillIsBookedProvisionallyBeforeTheFirstAnswer() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:10")
        #expect(h.timeline == ["Writing 08:00-08:10"])
        #expect(h.tracker.mode == .tracking)
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
        var h = Harness()
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.reading))
        h.pass(to: "08:20")
        #expect(h.timeline == ["Reading 08:00-08:20"])
    }

    @Test func sameActivityGetsTheWholeSpan() {
        var h = Harness()
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
        var h = Harness()
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
