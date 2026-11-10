#if DEBUG
    import Foundation
    import WamaduCore

    /// Synthetic day for screenshots.
    extension DashboardView {
        static let sampleCodeReviewId: Int64 = 1

        static func sample(
            _ current: NowRow, empty: Bool = false, done: Bool = false, model: AppModel
        ) -> DashboardView {
            let calendar = Calendar.current
            let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
            func at(_ hour: Int, _ minute: Int = 0) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            let customers = [
                Customer(id: 1, name: "Acme", colorIndex: 0), Customer(id: 2, name: "Northwind", colorIndex: 1),
            ]
            let projects = [
                Project(id: 1, name: "Relaunch", customerId: 1), Project(id: 2, name: "Shop 2.0", customerId: 2),
            ]
            let activities = [
                Activity(id: sampleCodeReviewId, name: "Code Review", projectId: 1),
                Activity(id: 2, name: "Planning", projectId: 1),
                Activity(id: 3, name: "Support", customerId: 1),
                Activity(id: 4, name: "Kickoff", projectId: 2),
                Activity(id: 5, name: "Weekly"),
                Activity(id: 6, name: "Email"),
                Activity(id: 7, name: "Break", kind: .break),
            ]
            let spans: [(Int64, Date, Date)] = [
                (6, at(8, 30), at(9)), (5, at(9), at(10)), (1, at(10), at(12, 15)), (7, at(12, 15), at(13)),
                (2, at(13), at(14, 30)), (4, at(14, 30), at(16)), (3, at(16), at(16, 30)), (1, at(16, 30), at(17)),
            ]
            let blocks =
                empty ? [] : spans.map { Block(activityId: $0.0, startedAt: $0.1, endedAt: $0.2, source: .checkIn) }
            let data = DashboardData(
                period: Period(.day, containing: day, calendar: calendar), blocks: blocks, activities: activities,
                projects: projects, customers: customers,
                schedule: WorkSchedule(plans: [2: .init(start: 9 * 60, end: 17 * 60)]), current: current,
                now: empty ? at(8, 50) : at(17, 30), calendar: calendar)
            return DashboardView(
                data: data, done: done, moreActions: MoreActionsMenu(model: model), onShowPeriod: { _ in },
                onCheckIn: {}, onKeepTracking: {})
        }
    }
#endif
