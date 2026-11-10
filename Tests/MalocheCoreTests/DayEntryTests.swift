import Foundation
import Testing

@testable import MalocheCore

@Suite struct DayEntryTests {
    private let day = Fixture.span("00:00", "2026-11-10 00:00")

    private func block(_ id: Int64, _ activityId: Int64, _ from: String, _ to: String) -> Block {
        Block(id: id, activityId: activityId, startedAt: Fixture.at(from), endedAt: Fixture.at(to), source: .checkIn)
    }

    @Test func touchingBlocksOfTheActivityMergeIntoOneSpan() throws {
        let blocks = [
            block(3, Fixture.writing, "16:00", "17:00"), block(2, Fixture.writing, "11:00", "12:15"),
            block(1, Fixture.writing, "10:00", "11:00"),
        ]
        let entry = try #require(DayEntry(activityId: Fixture.writing, day: day, blocks: blocks))
        #expect(entry.activityId == Fixture.writing)
        #expect(entry.day == day)
        #expect(entry.spans.map(\.interval) == [Fixture.span("10:00", "12:15"), Fixture.span("16:00", "17:00")])
        #expect(entry.spans.map(\.blockIds) == [[1, 2], [3]])
        #expect(entry.blockIds == [1, 2, 3])
    }

    @Test func otherActivitiesBetweenSeparateTheSpans() throws {
        let blocks = [
            block(1, Fixture.writing, "09:00", "10:00"), block(2, Fixture.reading, "10:00", "10:30"),
            block(3, Fixture.writing, "10:30", "11:00"), block(4, Fixture.meeting, "11:00", "12:00"),
        ]
        let entry = try #require(DayEntry(activityId: Fixture.writing, day: day, blocks: blocks))
        #expect(entry.spans.map(\.interval) == [Fixture.span("09:00", "10:00"), Fixture.span("10:30", "11:00")])
        #expect(entry.spans.map(\.blockIds) == [[1], [3]])
    }

    @Test func blocksOfOtherDaysStayOutAndBlocksOverMidnightKeepTheirTimes() throws {
        let blocks = [
            block(1, Fixture.writing, "2026-11-08 20:00", "2026-11-08 21:00"),
            block(2, Fixture.writing, "2026-11-08 23:00", "01:00"),
            block(3, Fixture.writing, "23:30", "2026-11-10 00:30"),
            block(4, Fixture.writing, "2026-11-10 08:00", "2026-11-10 09:00"),
        ]
        let entry = try #require(DayEntry(activityId: Fixture.writing, day: day, blocks: blocks))
        #expect(
            entry.spans.map(\.interval) == [
                Fixture.span("2026-11-08 23:00", "01:00"), Fixture.span("23:30", "2026-11-10 00:30"),
            ])
        #expect(entry.blockIds == [2, 3])
    }

    @Test func anActivityWithoutTimeOnTheDayHasNoEntry() {
        let blocks = [
            block(1, Fixture.reading, "09:00", "10:00"),
            block(2, Fixture.writing, "2026-11-08 09:00", "2026-11-08 10:00"),
        ]
        #expect(DayEntry(activityId: Fixture.writing, day: day, blocks: blocks) == nil)
    }
}
