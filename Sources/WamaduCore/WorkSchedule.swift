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

    /// The plan on the local day of `date`, resolved through the calendar so DST days keep their wall-clock times.
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
}
