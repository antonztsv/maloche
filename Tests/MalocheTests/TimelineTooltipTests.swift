import Foundation
import MalocheCore
import Testing

@testable import Maloche

@MainActor @Suite struct TimelineTooltipTests {
    private let calendar = Calendar.current
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))! }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func span(_ from: Date, _ to: Date) -> String {
        "\(from.formatted(DashboardData.time)) to \(to.formatted(DashboardData.time))"
    }

    /// "22:01:02 to 22:01:08" and "6 seconds" for an entry under a minute, the same in tooltip, menu and confirmation.
    @Test func anEntryUnderAMinuteIsNamedInSeconds() throws {
        let start = calendar.date(bySettingHour: 22, minute: 1, second: 2, of: day)!
        let end = start + 6
        let data = DashboardData(
            period: Period(.day, containing: day, calendar: calendar),
            blocks: [Block(activityId: 1, startedAt: start, endedAt: end, source: .checkIn)],
            activities: [Activity(id: 1, name: "Test")], projects: [], customers: [], current: .none,
            now: at(23), calendar: calendar)
        let bar = try #require(data.bars.first)
        let seconds =
            "\(start.formatted(DashboardData.timeWithSeconds)) to \(end.formatted(DashboardData.timeWithSeconds))"
        #expect(DashboardData.span(bar.interval) == seconds)
        #expect(data.entryName(bar) == "Test, \(seconds)")
        #expect(data.tooltip(of: bar) == "Test\n\(DurationFormat.spoken(6)), \(seconds)")
        #expect(data.deleteMessage(bar).hasPrefix("Test, \(seconds). "))
        #expect(data.deleteMessage(bar).contains(DurationFormat.spoken(6)))
        #expect(DashboardData.span(DateInterval(start: start, duration: 60)) == span(start, start + 60))
    }

    @Test func eachBlockNamesActivityProjectCustomerDurationAndSpan() throws {
        let blocks = [
            Block(activityId: 1, startedAt: at(10), endedAt: at(11), source: .checkIn),
            Block(activityId: 1, startedAt: at(11), endedAt: at(12, 15), source: .checkIn),
            Block(activityId: 2, startedAt: at(12, 15), endedAt: at(13), source: .checkIn),
            Block(activityId: 3, startedAt: at(13), endedAt: at(13, 30), source: .checkIn),
            Block(activityId: 4, startedAt: at(13, 30), endedAt: at(14), source: .checkIn),
        ]
        let data = DashboardData(
            period: Period(.day, containing: day, calendar: calendar), blocks: blocks,
            activities: [
                Activity(id: 1, name: "Code Review", projectId: 1), Activity(id: 2, name: "Break", kind: .break),
                Activity(id: 3, name: "Weekly"), Activity(id: 4, name: "Support", customerId: 1),
            ],
            projects: [Project(id: 1, name: "Relaunch", customerId: 1)],
            customers: [Customer(id: 1, name: "Acme", colorIndex: 0)], current: .none, now: at(14, 5),
            calendar: calendar)
        #expect(
            data.bars.map(data.tooltip) == [
                "Code Review, Relaunch, Acme\n2:15, \(span(at(10), at(12, 15)))",
                "Break\n0:45, \(span(at(12, 15), at(13)))",
                "Weekly\n0:30, \(span(at(13), at(13, 30)))",
                "Support, Acme\n0:30, \(span(at(13, 30), at(14)))",
            ])
    }
}
