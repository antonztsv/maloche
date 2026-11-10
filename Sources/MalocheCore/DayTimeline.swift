import Foundation

/// A day's blocks on an axis spanning plan and blocks; positions are elapsed time, so DST days keep true lengths.
public struct DayTimeline: Equatable, Sendable {
    public struct Segment<Key: Equatable & Sendable>: Equatable, Sendable {
        public var key: Key
        public var interval: DateInterval
        /// Axis positions, 0 at the range start and 1 at its end.
        public var start: Double
        public var end: Double
    }

    public var range: DateInterval

    /// Nil when no block falls on the day; blocks and plan are clipped to the day.
    public init?(day: DateInterval, blocks: [Block], plan: DateInterval?) {
        let clipped = blocks.compactMap { $0.interval.intersection(with: day) }.filter { $0.duration > 0 }
        guard let first = clipped.map(\.start).min(), let last = clipped.map(\.end).max() else { return nil }
        let plan = plan?.intersection(with: day)
        range = DateInterval(start: min(first, plan?.start ?? first), end: max(last, plan?.end ?? last))
    }

    public func fraction(of date: Date) -> Double {
        date.timeIntervalSince(range.start) / range.duration
    }

    /// Time ordered; touching blocks with the same key merge into one segment.
    public func segments<Key>(of blocks: [Block], key: (Block) -> Key) -> [Segment<Key>] {
        var segments: [Segment<Key>] = []
        for block in blocks.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let interval = block.interval.intersection(with: range), interval.duration > 0 else { continue }
            let key = key(block)
            if let last = segments.last, last.key == key, last.interval.end == interval.start {
                segments[segments.count - 1].interval.end = interval.end
                segments[segments.count - 1].end = fraction(of: interval.end)
            } else {
                segments.append(
                    Segment(
                        key: key, interval: interval, start: fraction(of: interval.start),
                        end: fraction(of: interval.end)))
            }
        }
        return segments
    }

    /// Every second hour from the first full local hour, two elapsed hours apart.
    public func hourTicks(calendar: Calendar) -> [Date] {
        guard let hour = calendar.dateInterval(of: .hour, for: range.start) else { return [] }
        let first = hour.start == range.start ? hour.start : hour.end
        return Array(stride(from: first, through: range.end, by: 2 * 3600))
    }
}
