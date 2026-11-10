import Foundation
import Testing

@testable import MalocheCore

@Suite struct DayTimelineTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func local(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func dayInterval(_ day: Int, month: Int = 11) -> DateInterval {
        calendar.dateInterval(of: .day, for: local(day, 12, month: month))!
    }

    private func block(_ activityId: Int64, _ from: Date, _ to: Date) -> Block {
        Block(activityId: activityId, startedAt: from, endedAt: to, source: .checkIn)
    }

    private func hours(_ dates: [Date]) -> [Int] {
        dates.map { calendar.component(.hour, from: $0) }
    }

    @Test func rangeRunsFromFirstToLastBlockWithoutPlan() throws {
        let blocks = [block(1, local(9, 8, 30), local(9, 9, 30)), block(2, local(9, 16), local(9, 17))]
        let timeline = try #require(DayTimeline(day: dayInterval(9), blocks: blocks, plan: nil))
        #expect(timeline.range == DateInterval(start: local(9, 8, 30), end: local(9, 17)))
        #expect(timeline.fraction(of: local(9, 9, 30)) == 60.0 / 510)
        #expect(timeline.fraction(of: local(9, 17)) == 1)
    }

    @Test func planWidensTheRangeAndLaterBlocksWidenThePlan() throws {
        let blocks = [block(1, local(9, 8, 30), local(9, 17))]
        let wide = try #require(
            DayTimeline(day: dayInterval(9), blocks: blocks, plan: .init(start: local(9, 8), end: local(9, 18))))
        #expect(wide.range == DateInterval(start: local(9, 8), end: local(9, 18)))
        let narrow = try #require(
            DayTimeline(day: dayInterval(9), blocks: blocks, plan: .init(start: local(9, 9), end: local(9, 16))))
        #expect(narrow.range == DateInterval(start: local(9, 8, 30), end: local(9, 17)))
    }

    @Test func blocksAreClippedToTheDay() throws {
        let blocks = [block(1, local(8, 23), local(9, 1))]
        let timeline = try #require(DayTimeline(day: dayInterval(9), blocks: blocks, plan: nil))
        #expect(timeline.range == DateInterval(start: local(9, 0), end: local(9, 1)))
        #expect(timeline.segments(of: blocks) { $0.activityId }.map(\.interval) == [timeline.range])
    }

    @Test func dayWithoutBlocksHasNoTimeline() {
        let blocks = [block(1, local(8, 9), local(8, 17))]
        #expect(
            DayTimeline(day: dayInterval(9), blocks: blocks, plan: .init(start: local(9, 8), end: local(9, 18))) == nil)
    }

    @Test func touchingBlocksWithTheSameKeyMerge() throws {
        let blocks = [
            block(1, local(9, 9), local(9, 9, 15)), block(1, local(9, 9, 15), local(9, 10)),
            block(2, local(9, 10), local(9, 11)), block(1, local(9, 11), local(9, 12)),
            block(1, local(9, 13), local(9, 14)),
        ]
        let timeline = try #require(DayTimeline(day: dayInterval(9), blocks: blocks.reversed(), plan: nil))
        let segments = timeline.segments(of: blocks.reversed()) { $0.activityId }
        #expect(segments.map(\.key) == [1, 2, 1, 1])
        #expect(segments[0].interval == DateInterval(start: local(9, 9), end: local(9, 10)))
        #expect(segments[0].start == 0 && segments[0].end == 0.2)
        #expect(segments[3].start == 0.8 && segments[3].end == 1)
    }

    @Test func ticksEverySecondFullHour() throws {
        let board = try #require(
            DayTimeline(day: dayInterval(9), blocks: [block(1, local(9, 8, 30), local(9, 17))], plan: nil))
        #expect(hours(board.hourTicks(calendar: calendar)) == [9, 11, 13, 15, 17])
        let planned = try #require(
            DayTimeline(
                day: dayInterval(9), blocks: [block(1, local(9, 9), local(9, 10))],
                plan: .init(start: local(9, 8), end: local(9, 18))))
        #expect(hours(planned.hourTicks(calendar: calendar)) == [8, 10, 12, 14, 16, 18])
    }

    @Test func springForwardKeepsElapsedTime() throws {
        let blocks = [block(1, local(29, 0, 30, month: 3), local(29, 7, month: 3))]
        let timeline = try #require(DayTimeline(day: dayInterval(29, month: 3), blocks: blocks, plan: nil))
        #expect(timeline.range.duration == 5.5 * 3600)
        #expect(timeline.fraction(of: local(29, 4, month: 3)) == 2.5 / 5.5)
        #expect(hours(timeline.hourTicks(calendar: calendar)) == [1, 4, 6])
    }

    @Test func fallBackKeepsElapsedTime() throws {
        let blocks = [block(1, local(25, 0, month: 10), local(25, 6, month: 10))]
        let timeline = try #require(DayTimeline(day: dayInterval(25, month: 10), blocks: blocks, plan: nil))
        #expect(timeline.range.duration == 7 * 3600)
        #expect(hours(timeline.hourTicks(calendar: calendar)) == [0, 2, 3, 5])
    }
}
