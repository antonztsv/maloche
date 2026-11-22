import AppKit
import MalocheCore
import SwiftUI

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
    /// Activities whose rows and blocks open Manage Activities.
    var manageable: Set<Int64> = []
    /// The block being booked right now, its entry has no Delete.
    var runningEntry: RunningEntry?

    init(
        period: Period, blocks: [Block], activities: [Activity], projects: [Project], customers: [Customer],
        current: NowRow, now: Date, calendar: Calendar,
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
        guard period.kind == .day else { return }
        let shown = blocks.filter { block in self.activities[block.activityId].map { $0.kind != .private } ?? false }
        timeline = DayTimeline(day: period.interval, blocks: shown, now: now, calendar: calendar)
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

    /// "Code Review, Relaunch, Acme" over "2:15, 10:00 to 12:15", breaks as "Break".
    func tooltip(of bar: DayTimeline.Segment<Int64>) -> String {
        let activity = activities[bar.key]
        let names =
            isBreak(bar.key)
            ? [String(localized: "Break")]
            : [activity?.name, activity?.projectId.flatMap { projects[$0]?.name }, customer(of: bar.key)?.name]
                .compactMap { $0 }
        return names.joined(separator: ", ") + "\n" + DurationFormat.hoursMinutes(bar.interval.duration) + ", "
            + Self.span(bar.interval)
    }

    /// "Code Review, 0:10 to 0:15", the entry as the context menu names it.
    func entryName(_ bar: DayTimeline.Segment<Int64>) -> String {
        "\(activityName(bar.key)), \(Self.span(bar.interval))"
    }

    /// "Code Review, Nordlicht GmbH, 0:10 to 0:15. This removes 5 minutes from today. You can’t undo this."
    func deleteMessage(_ bar: DayTimeline.Segment<Int64>) -> String {
        let entry =
            ([activityName(bar.key)] + (isBreak(bar.key) ? [] : [customer(of: bar.key)?.name].compactMap { $0 })
            + [Self.span(bar.interval)]).joined(separator: ", ")
        let duration = DurationFormat.spoken(bar.interval.duration)
        return isCurrent
            ? String(localized: "\(entry). This removes \(duration) from today. You can’t undo this.")
            : String(localized: "\(entry). This removes \(duration) from this day. You can’t undo this.")
    }

    func isDeletable(_ bar: DayTimeline.Segment<Int64>) -> Bool {
        runningEntry?.contains(activityId: bar.key, interval: bar.interval) != true
    }

    private func activityName(_ id: Int64) -> String {
        isBreak(id) ? String(localized: "Break") : activities[id]?.name ?? ""
    }

    static func span(_ interval: DateInterval) -> String {
        String(localized: "\(interval.start, format: time) to \(interval.end, format: time)")
    }

    static func name(of customer: Customer?) -> String {
        customer?.name ?? String(localized: "Internal")
    }

    static func color(of customer: Customer?) -> Color {
        Color(nsColor: CustomerColor.nsColor(for: customer))
    }

    /// "8:30 to 10:00 Internal", for VoiceOver.
    static func spanLabel(_ interval: DateInterval, _ name: String) -> String {
        String(localized: "\(span(interval)) \(name)", comment: "A time span and what it was spent on, for VoiceOver")
    }

    /// Clock time in the system 12 or 24 hour format, without a leading zero.
    static let time = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)

    private static func byId<T: Identifiable>(_ items: [T]) -> [Int64: T] where T.ID == Int64? {
        Dictionary(items.compactMap { item in item.id.map { ($0, item) } }) { first, _ in first }
    }
}

extension Text {
    /// "7:45" on screen, "7 hours 45 minutes" for VoiceOver.
    init(duration: TimeInterval) {
        self = Text(verbatim: DurationFormat.hoursMinutes(duration)).accessibilityLabel(DurationFormat.spoken(duration))
    }
}
