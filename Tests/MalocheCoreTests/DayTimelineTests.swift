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

    private func timeline(_ day: Int, _ blocks: [Block], now: Date, month: Int = 11) throws -> DayTimeline {
        try #require(DayTimeline(day: dayInterval(day, month: month), blocks: blocks, now: now, calendar: calendar))
    }

    @Test func aPastDayRunsFromTheFirstToTheLastBlockOnFullHours() throws {
        let blocks = [block(1, local(9, 8, 30), local(9, 9, 30)), block(2, local(9, 16), local(9, 16, 40))]
        let timeline = try timeline(9, blocks, now: local(10, 12))
        #expect(timeline.range == DateInterval(start: local(9, 8), end: local(9, 17)))
        #expect(timeline.fraction(of: local(9, 9, 30)) == 1.5 / 9)
    }

    @Test func todayRunsUntilTheHourAfterNow() throws {
        let blocks = [block(1, local(17, 0, 4), local(17, 0, 17))]
        #expect(try timeline(17, blocks, now: local(17, 0, 20)).range == .init(start: local(17, 0), end: local(17, 1)))
        let morning = [block(1, local(17, 8, 30), local(17, 10))]
        let afternoon = try timeline(17, morning, now: local(17, 13, 10))
        #expect(afternoon.range == .init(start: local(17, 8), end: local(17, 14)))
    }

    @Test func todayGrowsWithTheClock() throws {
        let blocks = [block(1, local(17, 8, 30), local(17, 10))]
        #expect(try timeline(17, blocks, now: local(17, 10, 5)).range.end == local(17, 11))
        #expect(try timeline(17, blocks, now: local(17, 11, 30)).range.end == local(17, 12))
        #expect(try timeline(17, blocks, now: local(17, 12)).range.end == local(17, 12))
    }

    @Test func theAxisSpansAtLeastOneHour() throws {
        let short = [block(1, local(9, 9), local(9, 9, 15))]
        #expect(try timeline(9, short, now: local(10, 8)).range == .init(start: local(9, 9), end: local(9, 10)))
        let late = [block(1, local(9, 23, 30), local(9, 23, 50))]
        #expect(try timeline(9, late, now: local(10, 8)).range == .init(start: local(9, 23), end: local(10, 0)))
    }

    @Test func blocksAreClippedToTheDay() throws {
        let blocks = [block(1, local(8, 23), local(9, 1))]
        let timeline = try timeline(9, blocks, now: local(10, 8))
        #expect(timeline.range == DateInterval(start: local(9, 0), end: local(9, 1)))
        #expect(timeline.segments(of: blocks) { $0.activityId }.map(\.interval) == [timeline.range])
    }

    @Test func dayWithoutBlocksHasNoTimeline() {
        let blocks = [block(1, local(8, 9), local(8, 17))]
        #expect(DayTimeline(day: dayInterval(9), blocks: blocks, now: local(9, 12), calendar: calendar) == nil)
    }

    /// Spans in points: 0 to 2, 100 to 300, 304 to 306.
    private let spans: [ClosedRange<Double>] = [0...2, 100...300, 304...306]

    @Test func thePointerSnapsToTheNearestBlockWithinEightPoints() {
        #expect(DayTimeline.nearest(to: 1, in: spans, radius: 8) == 0)
        #expect(DayTimeline.nearest(to: 9, in: spans, radius: 8) == 0)
        #expect(DayTimeline.nearest(to: 10.5, in: spans, radius: 8) == nil)
        #expect(DayTimeline.nearest(to: 93, in: spans, radius: 8) == 1)
        #expect(DayTimeline.nearest(to: 200, in: spans, radius: 8) == 1)
        #expect(DayTimeline.nearest(to: 309, in: spans, radius: 8) == 2)
        #expect(DayTimeline.nearest(to: 320, in: spans, radius: 8) == nil)
        #expect(DayTimeline.nearest(to: 5, in: [], radius: 8) == nil)
    }

    @Test func betweenTwoBlocksTheNearerEdgeWins() {
        #expect(DayTimeline.nearest(to: 301, in: spans, radius: 8) == 1)
        #expect(DayTimeline.nearest(to: 303, in: spans, radius: 8) == 2)
        #expect(DayTimeline.nearest(to: 55, in: [0...50, 58...60], radius: 8) == 1)
    }

    @Test func touchingBlocksWithTheSameKeyMerge() throws {
        let blocks = [
            block(1, local(9, 9), local(9, 9, 15)), block(1, local(9, 9, 15), local(9, 10)),
            block(2, local(9, 10), local(9, 11)), block(1, local(9, 11), local(9, 12)),
            block(1, local(9, 13), local(9, 14)),
        ]
        let timeline = try timeline(9, blocks.reversed(), now: local(10, 8))
        let segments = timeline.segments(of: blocks.reversed()) { $0.activityId }
        #expect(segments.map(\.key) == [1, 2, 1, 1])
        #expect(segments[0].interval == DateInterval(start: local(9, 9), end: local(9, 10)))
        #expect(segments[0].start == 0 && segments[0].end == 0.2)
        #expect(segments[3].start == 0.8 && segments[3].end == 1)
    }

    private func ticks(_ timeline: DayTimeline, width: Double) -> [Int] {
        hours(timeline.hourTicks(calendar: calendar, width: width, labelWidth: 30))
    }

    @Test func ticksTakeTheSmallestStepAtWhichNoLabelsTouch() throws {
        let day = try timeline(9, [block(1, local(9, 8, 30), local(9, 16, 40))], now: local(10, 8))
        #expect(ticks(day, width: 900) == Array(8...17))
        #expect(ticks(day, width: 180) == [9, 12, 15])
        #expect(ticks(day, width: 40) == [12])
    }

    @Test func labelsAtTheEdgesStayInsideWithoutTouchingTheirNeighbour() throws {
        let day = try timeline(9, [block(1, local(9, 8), local(9, 18))], now: local(10, 8))
        let labels = day.hourTicks(calendar: calendar, width: 300, labelWidth: 30)
        let centers = labels.map { min(max(day.fraction(of: $0) * 300, 15), 285) }
        #expect(zip(centers, centers.dropFirst()).allSatisfy { $1 - $0 >= 30 + 8 }, "\(hours(labels))")
        #expect(hours(labels) == [8, 10, 12, 14, 16, 18])
    }

    @Test func springForwardKeepsElapsedTime() throws {
        let blocks = [block(1, local(29, 0, 30, month: 3), local(29, 6, 40, month: 3))]
        let timeline = try timeline(29, blocks, now: local(30, 8, month: 3), month: 3)
        #expect(timeline.range.duration == 6 * 3600)
        #expect(timeline.fraction(of: local(29, 4, month: 3)) == 3.0 / 6)
        #expect(ticks(timeline, width: 600) == [0, 1, 3, 4, 5, 6, 7])
        #expect(ticks(timeline, width: 240) == [0, 4, 6])
    }

    @Test func fallBackKeepsElapsedTime() throws {
        let blocks = [block(1, local(25, 0, month: 10), local(25, 6, month: 10))]
        let timeline = try timeline(25, blocks, now: local(26, 8, month: 10), month: 10)
        #expect(timeline.range.duration == 7 * 3600)
        #expect(ticks(timeline, width: 700) == [0, 1, 2, 2, 3, 4, 5, 6])
    }
}
