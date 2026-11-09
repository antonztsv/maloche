import Foundation

public enum PeriodKind: Sendable {
    case day, week, month
}

/// A local day, week or month; time zone and first weekday come from the calendar.
public struct Period: Equatable, Sendable {
    public var kind: PeriodKind
    public var interval: DateInterval

    public init(_ kind: PeriodKind, containing date: Date, calendar: Calendar) {
        let component: Calendar.Component =
            switch kind {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            }
        self.kind = kind
        self.interval = calendar.dateInterval(of: component, for: date)!
    }

    public func next(calendar: Calendar) -> Period {
        Period(kind, containing: interval.end, calendar: calendar)
    }

    public func previous(calendar: Calendar) -> Period {
        Period(kind, containing: interval.start.addingTimeInterval(-1), calendar: calendar)
    }

    public func days(calendar: Calendar) -> [DateInterval] {
        var days: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end {
            let day = calendar.dateInterval(of: .day, for: cursor)!
            days.append(day)
            cursor = day.end
        }
        return days
    }
}

public struct DaySummary: Equatable, Sendable {
    public var interval: DateInterval
    public var work: TimeInterval = 0
    public var breaks: TimeInterval = 0
    /// Start of the first and end of the last work or break block, clipped to the day.
    public var start: Date?
    public var end: Date?
    /// Work per customer id, nil for activities without a customer.
    public var workByCustomer: [Int64?: TimeInterval] = [:]
}

/// Touching work or break blocks of one activity clipped to one local day, the unit that rounding works on.
public struct ReportEntry: Equatable, Sendable {
    public var day: Date
    public var activityId: Int64
    public var duration: TimeInterval
}

public struct ActivityTotal: Equatable, Sendable {
    public var activity: Activity
    public var duration: TimeInterval
}

public struct ProjectTotal: Equatable, Sendable {
    public var project: Project?
    public var duration: TimeInterval
    public var activities: [ActivityTotal]
}

public struct CustomerTotal: Equatable, Sendable {
    public var customer: Customer?
    public var duration: TimeInterval
    public var projects: [ProjectTotal]
}

/// Exact durations; work and break are separate, Private counts as neither and lists hold work only.
public struct PeriodSummary: Equatable, Sendable {
    public var period: Period
    public var work: TimeInterval
    public var breaks: TimeInterval
    public var days: [DaySummary]
    /// Longest first.
    public var activities: [ActivityTotal]
    /// Longest first, with projects and activities longest first.
    public var customers: [CustomerTotal]
    public var entries: [ReportEntry]

    public var daysWithWork: Int { days.count { $0.work > 0 } }
    public var averageWorkPerDay: TimeInterval { daysWithWork == 0 ? 0 : work / Double(daysWithWork) }
}

public enum Reports {
    public static func summary(
        of period: Period, blocks: [Block], activities: [Activity], projects: [Project], customers: [Customer],
        calendar: Calendar
    ) -> PeriodSummary {
        let activitiesById = activities.byId
        let projectsById = projects.byId
        let customersById = customers.byId
        var days: [DaySummary] = []
        var entries: [ReportEntry] = []
        var workByActivity: [Int64: TimeInterval] = [:]
        let blocks = blocks.sorted { $0.startedAt < $1.startedAt }
        for interval in period.days(calendar: calendar) {
            var day = DaySummary(interval: interval)
            var lastEnd: Date?
            for block in blocks {
                guard let activity = activitiesById[block.activityId], activity.kind != .private else { continue }
                let start = max(block.startedAt, interval.start)
                let end = min(block.endedAt, interval.end)
                guard start < end else { continue }
                let duration = end.timeIntervalSince(start)
                if lastEnd == start, entries.last?.activityId == block.activityId {
                    entries[entries.count - 1].duration += duration
                } else {
                    entries.append(ReportEntry(day: interval.start, activityId: block.activityId, duration: duration))
                }
                lastEnd = end
                day.start = min(day.start ?? start, start)
                day.end = max(day.end ?? end, end)
                if activity.kind == .break {
                    day.breaks += duration
                } else {
                    day.work += duration
                    day.workByCustomer[activity.customerId(projects: projectsById), default: 0] += duration
                    workByActivity[block.activityId, default: 0] += duration
                }
            }
            days.append(day)
        }

        let activityTotals = longestFirst(
            workByActivity.map { ActivityTotal(activity: activitiesById[$0.key]!, duration: $0.value) }, \.duration
        ) { $0.activity.name }
        let customerTotals = Dictionary(grouping: activityTotals) { $0.activity.customerId(projects: projectsById) }
            .map { customerId, activityTotals in
                let projectTotals = Dictionary(grouping: activityTotals) { total in
                    total.activity.projectId.flatMap { projectsById[$0]?.id }
                }
                .map { projectId, activityTotals in
                    ProjectTotal(
                        project: projectId.flatMap { projectsById[$0] }, duration: sum(activityTotals),
                        activities: activityTotals)
                }
                return CustomerTotal(
                    customer: customerId.flatMap { customersById[$0] }, duration: sum(activityTotals),
                    projects: longestFirst(projectTotals, \.duration) { $0.project?.name ?? "" })
            }

        return PeriodSummary(
            period: period, work: days.reduce(0) { $0 + $1.work }, breaks: days.reduce(0) { $0 + $1.breaks },
            days: days, activities: activityTotals,
            customers: longestFirst(customerTotals, \.duration) { $0.customer?.name ?? "" }, entries: entries)
    }

    private static func sum(_ totals: [ActivityTotal]) -> TimeInterval {
        totals.reduce(0) { $0 + $1.duration }
    }

    private static func longestFirst<T>(_ items: [T], _ duration: KeyPath<T, TimeInterval>, _ name: (T) -> String)
        -> [T]
    {
        items.sorted { ($0[keyPath: duration], name($1)) > ($1[keyPath: duration], name($0)) }
    }
}

extension Activity {
    /// The project's customer when the activity has a project, otherwise its own.
    func customerId(projects: [Int64: Project]) -> Int64? {
        if let projectId, let project = projects[projectId] { project.customerId } else { customerId }
    }
}

extension Array where Element: Identifiable, Element.ID == Int64? {
    var byId: [Int64: Element] {
        Dictionary(compactMap { item in item.id.map { ($0, item) } }) { first, _ in first }
    }
}
