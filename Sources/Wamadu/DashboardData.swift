import AppKit
import SwiftUI
import WamaduCore

/// Everything the dashboard shows of a day, week or month, built from database values; rounding changes durations,
/// never the timeline.
struct DashboardData {
    /// Timeline colors: work per customer, nil for activities without customer.
    enum Lane: Equatable, Sendable {
        case work(customerId: Int64?)
        case onBreak
    }

    var period: Period
    var summary: PeriodSummary
    var current: NowRow
    var now: Date
    /// The period contains now.
    var isCurrent: Bool
    var calendar: Calendar
    /// Nil on a day without work or break.
    var timeline: DayTimeline?
    /// Drawn blocks, touching blocks of one activity merged.
    var bars: [DayTimeline.Segment<Int64>] = []
    /// Spoken blocks, touching blocks of one customer merged.
    var lanes: [DayTimeline.Segment<Lane>] = []
    var activities: [Int64: Activity]
    var projects: [Int64: Project]
    var customers: [Int64: Customer]
    /// Activities whose rows and blocks open the entry editor.
    var editable: Set<Int64> = []

    init(
        period: Period, blocks: [Block], activities: [Activity], projects: [Project], customers: [Customer],
        schedule: WorkSchedule, current: NowRow, now: Date, calendar: Calendar,
        rounding: RoundingSettings = RoundingSettings()
    ) {
        self.period = period
        self.current = current
        self.now = now
        self.calendar = calendar
        self.isCurrent = period.interval.contains(now)
        self.activities = Self.byId(activities)
        self.projects = Self.byId(projects)
        self.customers = Self.byId(customers)
        summary = Reports.summary(
            of: period, blocks: blocks, activities: activities, projects: projects, customers: customers,
            calendar: calendar
        ).rounded(by: rounding)
        let shown = blocks.filter { block in self.activities[block.activityId].map { $0.kind != .private } ?? false }
        timeline = DayTimeline(
            day: period.interval, blocks: shown, plan: schedule.interval(on: period.interval.start, calendar: calendar))
        if let timeline {
            bars = timeline.segments(of: shown) { $0.activityId }
            lanes = timeline.segments(of: shown) { lane(of: $0.activityId) }
        }
    }

    var day: DaySummary? { summary.days.first }

    /// The period right before the current one.
    var isPrevious: Bool { !isCurrent && period.next(calendar: calendar).interval.contains(now) }

    func isBreak(_ activityId: Int64) -> Bool { activities[activityId]?.kind == .break }

    func lane(of activityId: Int64) -> Lane {
        isBreak(activityId) ? .onBreak : .work(customerId: customer(of: activityId)?.id)
    }

    /// The project's customer when the activity has a project, otherwise its own.
    func customer(of activityId: Int64) -> Customer? {
        guard let activity = activities[activityId] else { return nil }
        let customerId =
            if let projectId = activity.projectId, let project = projects[projectId] {
                project.customerId
            } else {
                activity.customerId
            }
        return customerId.flatMap { customers[$0] }
    }

    static func name(of customer: Customer?) -> String {
        customer?.name ?? String(localized: "Internal")
    }

    static func color(of customer: Customer?) -> Color {
        Color(nsColor: CustomerColor.nsColor(for: customer))
    }

    static func duration(_ seconds: TimeInterval) -> String { DurationFormat.hoursMinutes(seconds) }

    /// Clock time in the system 12 or 24 hour format, without a leading zero.
    static let time = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)

    private static func byId<T: Identifiable>(_ items: [T]) -> [Int64: T] where T.ID == Int64? {
        Dictionary(items.compactMap { item in item.id.map { ($0, item) } }) { first, _ in first }
    }
}
