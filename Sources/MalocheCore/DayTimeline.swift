import Foundation

/// A day's blocks on an axis of full hours from the first block to the last, today until now, so it grows during the
/// day; positions are elapsed time, so DST days keep true lengths.
public struct DayTimeline: Equatable, Sendable {
    public struct Segment<Key: Equatable & Sendable>: Equatable, Sendable {
        public var key: Key
        public var interval: DateInterval
        /// Axis positions, 0 at the range start and 1 at its end.
        public var start: Double
        public var end: Double
    }

    public var range: DateInterval

    /// Nil when no block falls on the day; blocks are clipped to the day, the axis spans at least an hour.
    public init?(day: DateInterval, blocks: [Block], now: Date, calendar: Calendar) {
        let clipped = blocks.compactMap { $0.interval.intersection(with: day) }.filter { $0.duration > 0 }
        guard let first = clipped.map(\.start).min(), var last = clipped.map(\.end).max(),
            let start = calendar.dateInterval(of: .hour, for: first)?.start
        else { return nil }
        if day.contains(now) { last = max(last, now) }
        let hour = calendar.dateInterval(of: .hour, for: last)
        let end = hour.map { $0.start == last ? last : $0.end } ?? last
        range = DateInterval(start: start, end: min(max(end, start + 3600), day.end))
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

    /// Full local hours in the smallest step of 1, 2, 3, 4 or 6 hours at which no labels touch; labels past an edge
    /// sit inside it. Should even 6 hours be too dense, labels that would touch the one before are left out.
    public func hourTicks(calendar: Calendar, width: Double, labelWidth: Double, gap: Double = 8) -> [Date] {
        let hours = fullHours(calendar: calendar)
        func center(_ date: Date) -> Double {
            min(max(fraction(of: date) * width, labelWidth / 2), width - labelWidth / 2)
        }
        var ticks: [Date] = []
        for step in [1, 2, 3, 4, 6] {
            let candidates = hours.filter { calendar.component(.hour, from: $0) % step == 0 }
            ticks = []
            for date in candidates where ticks.last.map({ center(date) - center($0) >= labelWidth + gap }) ?? true {
                ticks.append(date)
            }
            if ticks.count == candidates.count { break }
        }
        return ticks
    }

    /// Every full local hour on the axis, ends included.
    public func fullHours(calendar: Calendar) -> [Date] {
        guard let hour = calendar.dateInterval(of: .hour, for: range.start) else { return [] }
        return Array(stride(from: hour.start == range.start ? hour.start : hour.end, through: range.end, by: 3600))
    }
}
