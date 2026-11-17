import Foundation

/// Working hours per weekday in local wall-clock time.
public struct WorkSchedule: Codable, Equatable, Sendable {
    public struct Plan: Codable, Equatable, Sendable {
        /// Minutes after local midnight; a plan starts and ends on the same day.
        public var start: Int
        public var end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    /// Keyed by `Calendar` weekday, 1 is Sunday.
    public var plans: [Int: Plan]

    public init(plans: [Int: Plan]) {
        self.plans = plans
    }

    public static let standard = WorkSchedule(
        plans: Dictionary(uniqueKeysWithValues: (2...6).map { ($0, Plan(start: 8 * 60, end: 18 * 60)) }))

    /// The plan of the first planned day in the week of `calendar`, 8:00 to 18:00 when no day is planned.
    public func firstPlan(calendar: Calendar) -> Plan {
        calendar.orderedWeekdays.lazy.compactMap { plans[$0] }.first ?? Plan(start: 8 * 60, end: 18 * 60)
    }

    /// The plan with its stored start on the local day of `date`, resolved through the calendar so DST days keep their
    /// wall-clock times; tracking uses `workday(on:calendar:)`.
    public func interval(on date: Date, calendar: Calendar) -> DateInterval? {
        guard let plan = plans[calendar.component(.weekday, from: date)] else { return nil }
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        func at(_ minutes: Int) -> Date? {
            var time = day
            time.hour = minutes / 60
            time.minute = minutes % 60
            return calendar.date(from: time)
        }
        guard let start = at(plan.start), let end = at(plan.end), start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// From local midnight to the plan end of a work day; the day starts with the first use, not with `start`.
    public func workday(on date: Date, calendar: Calendar) -> DateInterval? {
        guard let plan = plans[calendar.component(.weekday, from: date)] else { return nil }
        let day = calendar.startOfDay(for: date)
        guard let end = calendar.date(bySettingHour: plan.end / 60, minute: plan.end % 60, second: 0, of: day),
            day < end
        else { return nil }
        return DateInterval(start: day, end: end)
    }
}

extension WorkSchedule.Plan {
    /// The end as the settings show it; the stored start, no longer used, moves before it so the plan stays valid.
    public var until: Int {
        get { end }
        set {
            end = newValue
            start = min(start, newValue - 1)
        }
    }
}
