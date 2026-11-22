import Foundation
import MalocheCore
import Testing

@testable import Maloche

/// One highlighted activity links a timeline bar and its row in the list.
@MainActor @Suite struct DashboardHighlightTests {
    private let groups: [(customer: Int64?, activities: [Int64])] = [(1, [10, 11]), (nil, [20])]

    @Test func aBarOrARowHighlightsItsActivity() throws {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let at = { (hour: Int) in calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)! }
        let data = DashboardData(
            period: Period(.day, containing: day, calendar: calendar),
            blocks: [
                Block(activityId: 1, startedAt: at(9), endedAt: at(10), source: .checkIn),
                Block(activityId: 2, startedAt: at(10), endedAt: at(11), source: .checkIn),
            ],
            activities: [Activity(id: 1, name: "Writing"), Activity(id: 2, name: "Review")], projects: [],
            customers: [], current: .none, now: at(12), calendar: calendar)
        #expect(data.activity(of: .bar(1)) == 2)
        #expect(data.activity(of: .row(1)) == 1)
        #expect(data.activity(of: .bar(7)) == nil)
        #expect(data.activity(of: nil) == nil)
    }

    @Test func theRowIsMarkedOrItsHeaderWhileTheGroupIsFolded() {
        #expect(DashboardList.mark(for: 11, in: groups, collapsed: []) == .row(11))
        #expect(DashboardList.mark(for: 11, in: groups, collapsed: [1]) == .header(1))
        #expect(DashboardList.mark(for: 20, in: groups, collapsed: [nil]) == .header(nil))
        #expect(DashboardList.mark(for: 20, in: groups, collapsed: [1]) == .row(20))
    }

    @Test func withoutARowNothingIsMarked() {
        #expect(DashboardList.mark(for: nil, in: groups, collapsed: []) == nil)
        #expect(DashboardList.mark(for: 99, in: groups, collapsed: []) == nil)
    }
}
