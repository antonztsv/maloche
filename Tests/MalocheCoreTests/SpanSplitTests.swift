import Foundation
import Testing

@testable import MalocheCore

@Suite struct SpanSplitTests {
    private func part(_ activity: Int64, _ start: String, _ end: String) -> Block {
        Block(activityId: activity, startedAt: Fixture.at(start), endedAt: Fixture.at(end), source: .split)
    }

    @Test func partsCoverTheSpanBetweenTheDividers() throws {
        let blocks = try SpanSplit.blocks(
            span: Fixture.span("08:00", "09:00"), dividers: [Fixture.at("08:20"), Fixture.at("08:45")],
            activities: [1, 2, 3])
        #expect(blocks == [part(1, "08:00", "08:20"), part(2, "08:20", "08:45"), part(3, "08:45", "09:00")])
    }

    @Test func fractionalDatesAreTruncatedWithoutDrift() throws {
        let span = DateInterval(start: Fixture.at("08:00") + 0.4, end: Fixture.at("09:00") + 0.9)
        let blocks = try SpanSplit.blocks(
            span: span, dividers: [Fixture.at("08:20") + 0.6, Fixture.at("08:40") + 0.5], activities: [1, 2, 3])
        #expect(blocks == [part(1, "08:00", "08:20"), part(2, "08:20", "08:40"), part(3, "08:40", "09:00")])
        #expect(blocks.map { $0.endedAt.timeIntervalSince($0.startedAt) }.reduce(0, +) == 3600)
    }

    @Test(arguments: [["07:59"], ["09:01"], ["08:00"], ["09:00"], ["08:40", "08:20"], ["08:20", "08:20"]])
    func rejectsDividersOutsideTheSpanOrOutOfOrder(_ dividers: [String]) {
        #expect(throws: SpanSplit.Failure.dividers) {
            try SpanSplit.blocks(
                span: Fixture.span("08:00", "09:00"), dividers: dividers.map(Fixture.at),
                activities: Array(repeating: 1, count: dividers.count + 1))
        }
    }

    @Test func rejectsAnActivityCountThatDoesNotMatchTheParts() {
        #expect(throws: SpanSplit.Failure.partCount) {
            try SpanSplit.blocks(span: Fixture.span("08:00", "09:00"), dividers: [Fixture.at("08:30")], activities: [1])
        }
    }

    @Test func dividersFromWholeMinutesLeaveTheRemainderToTheLastPart() throws {
        let span = Fixture.span("08:00", "09:07:30")
        let dividers = SpanSplit.dividers(start: span.start, minutes: [20, 25])
        #expect(dividers == [Fixture.at("08:20"), Fixture.at("08:45")])
        let blocks = try SpanSplit.blocks(span: span, dividers: dividers, activities: [1, 2, 3])
        #expect(blocks.last == part(3, "08:45", "09:07:30"))
    }

    @Test func checkInSplitBooksThePartsAndRunsTheLastOne() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "09:00")
        h.send(
            .checkInSplit(
                dividers: [Fixture.at("08:30"), Fixture.at("08:45")],
                activities: [Fixture.reading, Fixture.meeting, Fixture.writing]))
        #expect(
            h.timeline == ["Writing 08:00-08:15", "Reading 08:15-08:30", "Meeting 08:30-08:45", "Writing 08:45-09:00"])
        #expect(h.blocks.dropFirst().allSatisfy { $0.source == .split })
        h.pass(to: "09:10")
        #expect(h.timeline.last == "Writing 08:45-09:10")
    }

    @Test func splitEndingInBreakStartsTheBreakAtThatPart() {
        var h = Harness(settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "09:00")
        h.send(.checkInSplit(dividers: [Fixture.at("08:40")], activities: [Fixture.reading, Fixture.breakId]))
        #expect(h.tracker.mode == .onBreak)
        h.pass(to: "09:29", idle: true)
        h.pass(to: "09:30")
        #expect(h.takePrompts() == [.showBreakReturn(span: Fixture.span("08:40", "09:30"), prefill: Fixture.reading)])
        #expect(h.timeline == ["Writing 08:00-08:15", "Reading 08:15-08:40", "Break 08:40-09:30"])
    }

    @Test func splitEndingInPrivateRunsPrivateLikeAnActivity() {
        var h = Harness(settings: Fixture.noCheckIns)
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "09:00")
        h.send(.checkInSplit(dividers: [Fixture.at("08:40")], activities: [Fixture.breakId, Fixture.privateId]))
        #expect(h.tracker.mode == .tracking)
        #expect(h.tracker.currentActivity == Fixture.privateId)
        h.pass(to: "09:10")
        #expect(h.timeline == ["Writing 08:00-08:15", "Break 08:15-08:40", "Private 08:40-09:10"])
    }

    @Test func invalidSplitChangesNothing() {
        var h = Harness()
        h.tick()
        h.pass(to: "08:15")
        h.send(.checkInAnswered(Fixture.writing))
        h.pass(to: "08:45")
        h.send(.checkInSplit(dividers: [Fixture.at("08:10")], activities: [Fixture.reading, Fixture.meeting]))
        #expect(h.timeline == ["Writing 08:00-08:45"])
        h.send(.checkInAnswered(Fixture.reading))
        #expect(h.timeline == ["Writing 08:00-08:30", "Reading 08:30-08:45"])
    }
}
