import Foundation

public struct RoundingSettings: Equatable, Sendable {
    public enum Mode: Sendable {
        /// Halves round up.
        case nearest
        /// Any started step counts in full.
        case up
    }

    public enum Level: Sendable {
        /// Round each entry, then sum.
        case entry
        /// Sum per local day and activity, then round.
        case dayAndActivity
        /// Sum per activity over the period, then round.
        case period
    }

    /// Nil or 0 turns rounding off.
    public var stepMinutes: Int?
    public var mode: Mode
    public var level: Level

    public init(stepMinutes: Int?, mode: Mode, level: Level) {
        self.stepMinutes = stepMinutes
        self.mode = mode
        self.level = level
    }

    public func round(_ duration: TimeInterval) -> TimeInterval {
        guard let stepMinutes, stepMinutes > 0 else { return duration }
        let step = TimeInterval(stepMinutes * 60)
        // whole milliseconds first, Date arithmetic leaves float noise that would round up a full step
        let steps = (duration * 1000).rounded() / 1000 / step
        return (mode == .up ? steps.rounded(.up) : steps.rounded(.toNearestOrAwayFromZero)) * step
    }

    /// Per-day values are rounded per day and activity at the period level too, so they match the day view.
    public func apply(to entries: [ReportEntry]) -> RoundedTotals {
        var summed: [Date: [Int64: TimeInterval]] = [:]
        for entry in entries {
            summed[entry.day, default: [:]][entry.activityId, default: 0] +=
                level == .entry ? round(entry.duration) : entry.duration
        }
        let byDay = level == .entry ? summed : summed.mapValues { $0.mapValues(round) }
        var byActivity: [Int64: TimeInterval] = [:]
        for values in (level == .period ? summed : byDay).values {
            byActivity.merge(values, uniquingKeysWith: +)
        }
        return RoundedTotals(
            byActivity: level == .period ? byActivity.mapValues(round) : byActivity, byDayAndActivity: byDay)
    }
}

public struct RoundedTotals: Equatable, Sendable {
    public var byActivity: [Int64: TimeInterval]
    /// Keyed by the start of the local day.
    public var byDayAndActivity: [Date: [Int64: TimeInterval]]
}
