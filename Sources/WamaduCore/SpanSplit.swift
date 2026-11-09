import Foundation

/// Splits a span into parts at divider dates, as dragged in the split view.
public enum SpanSplit {
    public enum Failure: Error, Equatable {
        case partCount, dividers
    }

    /// One block per activity between the dividers, in whole seconds, so the durations sum exactly to the span.
    public static func blocks(span: DateInterval, dividers: [Date], activities: [Int64]) throws(Failure) -> [Block] {
        guard activities.count == dividers.count + 1 else { throw .partCount }
        let bounds = ([span.start] + dividers + [span.end]).map(Tracker.whole)
        guard zip(bounds, bounds.dropFirst()).allSatisfy({ $0 < $1 }) else { throw .dividers }
        return activities.indices.map {
            Block(activityId: activities[$0], startedAt: bounds[$0], endedAt: bounds[$0 + 1], source: .split)
        }
    }

    /// Dividers after the whole-minute durations of all parts but the last, which takes the remainder.
    public static func dividers(start: Date, minutes: [Int]) -> [Date] {
        var divider = Tracker.whole(start)
        return minutes.map {
            divider += TimeInterval($0 * 60)
            return divider
        }
    }
}
