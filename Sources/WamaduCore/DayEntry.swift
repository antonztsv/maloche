import Foundation

/// The spans of one activity on one day, as the edit popover shows them.
public struct DayEntry: Equatable, Sendable {
    public struct Span: Equatable, Sendable {
        /// Full block times, a span over midnight is not clipped to the day.
        public var interval: DateInterval
        /// The stored blocks the span covers, in time order.
        public var blockIds: [Int64]
    }

    public var activityId: Int64
    public var day: DateInterval
    /// Time ordered; touching blocks of the activity merge into one span.
    public var spans: [Span]

    /// Nil when no block of the activity falls on the day.
    public init?(activityId: Int64, day: DateInterval, blocks: [Block]) {
        var spans: [Span] = []
        for block in blocks.sorted(by: { $0.startedAt < $1.startedAt })
        where block.activityId == activityId && block.startedAt < day.end && day.start < block.endedAt {
            let ids = block.id.map { [$0] } ?? []
            if let last = spans.last, last.interval.end == block.startedAt {
                spans[spans.count - 1].interval.end = block.endedAt
                spans[spans.count - 1].blockIds += ids
            } else {
                spans.append(Span(interval: block.interval, blockIds: ids))
            }
        }
        guard !spans.isEmpty else { return nil }
        self.activityId = activityId
        self.day = day
        self.spans = spans
    }

    public var blockIds: [Int64] { spans.flatMap(\.blockIds) }
}
