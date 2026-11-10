import Foundation
import Testing

@testable import MalocheCore

@Suite struct RoundingTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let writing = Activity(id: 1, name: "Writing")
    private let review = Activity(id: 2, name: "Code Review")

    private func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func block(_ activity: Activity, day: Int, at hour: Int, minutes: Int) -> Block {
        Block(
            activityId: activity.id!, startedAt: local(day, hour), endedAt: local(day, hour, minutes),
            source: .checkIn)
    }

    /// Writing: four 4 min entries, two on Monday and two on Tuesday; Code Review: 22:30 min on Monday.
    private var blocks: [Block] {
        [
            block(writing, day: 9, at: 9, minutes: 4),
            block(writing, day: 9, at: 10, minutes: 4),
            block(writing, day: 10, at: 9, minutes: 4),
            block(writing, day: 10, at: 10, minutes: 4),
            Block(
                activityId: 2, startedAt: local(9, 11), endedAt: local(9, 11, 22).addingTimeInterval(30),
                source: .manual),
        ]
    }

    private func entries(_ blocks: [Block]) -> [ReportEntry] {
        Reports.summary(
            of: Period(.week, containing: local(9, 12), calendar: calendar), blocks: blocks,
            activities: [writing, review], projects: [], customers: [], calendar: calendar
        ).entries
    }

    @Test func roundsSingleValues() {
        let nearest = RoundingSettings(stepMinutes: 15, mode: .nearest, level: .entry)
        let up = RoundingSettings(stepMinutes: 15, mode: .up, level: .entry)
        #expect(nearest.round(7 * 60 + 29) == 0)
        #expect(up.round(7 * 60 + 29) == 15 * 60)
        #expect(nearest.round(7 * 60 + 30) == 15 * 60)
        #expect(nearest.round(22 * 60 + 30) == 30 * 60)
        #expect(nearest.round(22 * 60 + 29) == 15 * 60)
        #expect(up.round(0) == 0)
        #expect(up.round(15 * 60) == 15 * 60)
        #expect(up.round(15 * 60 + 1) == 30 * 60)
        #expect(up.round(900.000_000_1) == 15 * 60)
    }

    @Test func offReturnsExactValues() {
        for step in [nil, 0] {
            let settings = RoundingSettings(stepMinutes: step, mode: .up, level: .entry)
            #expect(settings.round(449) == 449)
            let totals = settings.apply(to: entries(blocks))
            #expect(totals.byActivity == [1: 16 * 60, 2: 22 * 60 + 30])
            #expect(totals.byDayAndActivity[local(9, 0)] == [1: 8 * 60, 2: 22 * 60 + 30])
            #expect(totals.byDayAndActivity[local(10, 0)] == [1: 8 * 60])
        }
    }

    @Test(
        arguments: [
            (RoundingSettings.Mode.nearest, RoundingSettings.Level.entry, 0, 0, 30),
            (.nearest, .dayAndActivity, 30, 15, 30),
            (.nearest, .period, 15, 15, 30),
            (.up, .entry, 60, 30, 30),
            (.up, .dayAndActivity, 30, 15, 30),
            (.up, .period, 30, 15, 30),
        ] as [(RoundingSettings.Mode, RoundingSettings.Level, Double, Double, Double)])
    func everyModeAndLevel(
        mode: RoundingSettings.Mode, level: RoundingSettings.Level, writingTotal: Double, writingPerDay: Double,
        reviewTotal: Double
    ) {
        let totals = RoundingSettings(stepMinutes: 15, mode: mode, level: level).apply(to: entries(blocks))
        #expect(totals.byActivity == [1: writingTotal * 60, 2: reviewTotal * 60])
        #expect(totals.byDayAndActivity[local(9, 0)] == [1: writingPerDay * 60, 2: reviewTotal * 60])
        #expect(totals.byDayAndActivity[local(10, 0)] == [1: writingPerDay * 60])
    }

    @Test func threeLevelsGiveThreeResults() {
        let results = [RoundingSettings.Level.entry, .dayAndActivity, .period].map { level in
            RoundingSettings(stepMinutes: 15, mode: .nearest, level: level).apply(to: entries(blocks)).byActivity[1]
        }
        #expect(results == [0, 30 * 60, 15 * 60])
    }

    @Test func touchingBlocksOfOneActivityAreRoundedAsOneEntry() {
        let split = [
            Block(activityId: 2, startedAt: local(9, 10, 20), endedAt: local(9, 10, 30), source: .split),
            Block(activityId: 2, startedAt: local(9, 10), endedAt: local(9, 10, 20), source: .checkIn),
        ]
        let totals = RoundingSettings(stepMinutes: 15, mode: .up, level: .entry).apply(to: entries(split))
        #expect(totals.byActivity == [2: 30 * 60])
    }

    @Test func inputsStayUnchanged() {
        let input = blocks
        let blocksCopy = input
        let reportEntries = entries(input)
        let entriesCopy = reportEntries
        for level in [RoundingSettings.Level.entry, .dayAndActivity, .period] {
            _ = RoundingSettings(stepMinutes: 15, mode: .up, level: level).apply(to: reportEntries)
        }
        #expect(input == blocksCopy)
        #expect(reportEntries == entriesCopy)
    }
}
