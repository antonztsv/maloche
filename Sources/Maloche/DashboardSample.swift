#if DEBUG
    import Foundation
    import MalocheCore

    /// Synthetic day, week and month for screenshots.
    extension DashboardView {
        static let sampleCodeReviewId: Int64 = 1
        private static let sampleCustomers = [
            Customer(id: 1, name: "Acme", colorIndex: 0), Customer(id: 2, name: "Northwind", colorIndex: 1),
        ]
        private static let sampleProjects = [
            Project(id: 1, name: "Relaunch", customerId: 1), Project(id: 2, name: "Shop 2.0", customerId: 2),
        ]
        private static let sampleActivities = [
            Activity(id: sampleCodeReviewId, name: "Code Review", projectId: 1),
            Activity(id: 2, name: "Planning", projectId: 1),
            Activity(id: 3, name: "Support", customerId: 1),
            Activity(id: 4, name: "Kickoff", projectId: 2),
            Activity(id: 5, name: "Weekly"),
            Activity(id: 6, name: "Email"),
            Activity(id: 7, name: "Break", kind: .break),
        ]

        static func sample(
            _ current: NowRow, empty: Bool = false, few: Bool = false, model: AppModel
        ) -> DashboardView {
            let calendar = Calendar.current
            let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
            func at(_ hour: Int, _ minute: Int = 0) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            let spans: [(Int64, Date, Date)] = [
                (6, at(8, 30), at(9)), (5, at(9), at(10)), (1, at(10), at(12, 15)), (7, at(12, 15), at(13)),
                (2, at(13), at(14, 30)), (4, at(14, 30), at(16)), (3, at(16), at(16, 30)), (1, at(16, 30), at(17)),
            ]
            let blocks =
                empty
                ? []
                : spans.prefix(few ? 2 : spans.count).map {
                    Block(activityId: $0.0, startedAt: $0.1, endedAt: $0.2, source: .checkIn)
                }
            var data = DashboardData(
                period: Period(.day, containing: day, calendar: calendar), blocks: blocks,
                activities: sampleActivities, projects: sampleProjects, customers: sampleCustomers,
                schedule: WorkSchedule(plans: [2: .init(start: 9 * 60, end: 17 * 60)]), current: current,
                now: empty ? at(8, 50) : few ? at(10, 5) : at(17, 30), calendar: calendar)
            data.editable = Set(blocks.map(\.activityId))
            return DashboardView(
                data: data, moreActions: MoreActionsMenu(model: model), onShowPeriod: { _ in },
                onCheckIn: {}, onKeepTracking: {})
        }

        /// Last week or October 2026 seen on November 10, each weekday Acme, a break, Northwind and Internal.
        static func sample(_ kind: PeriodKind, model: AppModel) -> DashboardView {
            let calendar = Calendar.current
            let shown = calendar.date(from: DateComponents(year: 2026, month: kind == .week ? 11 : 10, day: 2))!
            let period = Period(kind, containing: shown, calendar: calendar)
            let week = [[270, 120, 90], [300, 60, 90], [255, 150, 90], [270, 120, 75], [240, 120, 30]]
            let month = [465, 480, 450, 495, 420, 480, 240, 465, 510, 450]
            var blocks: [Block] = []
            for (index, day) in period.days(calendar: calendar).map(\.start).filter({ !calendar.isDateInWeekend($0) })
                .enumerated()
            {
                var minutes = week[index % week.count]
                if kind == .month {
                    let total = month[index % month.count]
                    let acme = total * 58 / 100 / 15 * 15
                    let northwind = total / 4 / 15 * 15
                    minutes = [acme, northwind, total - acme - northwind]
                }
                var start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
                for (activity, length) in zip([sampleCodeReviewId, 7, 4, 5], [minutes[0], 45, minutes[1], minutes[2]]) {
                    let end = start + TimeInterval(length * 60)
                    blocks.append(Block(activityId: activity, startedAt: start, endedAt: end, source: .checkIn))
                    start = end
                }
            }
            let data = DashboardData(
                period: period, blocks: blocks, activities: sampleActivities, projects: sampleProjects,
                customers: sampleCustomers, schedule: WorkSchedule(plans: [:]),
                current: .activity(id: sampleCodeReviewId),
                now: calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!, calendar: calendar)
            return DashboardView(
                data: data, moreActions: MoreActionsMenu(model: model), onShowPeriod: { _ in },
                onCheckIn: {}, onKeepTracking: {})
        }
    }
#endif
