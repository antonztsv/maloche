import Foundation

/// The parts of a span in the split view: dividers on whole minutes from its start, every part at least a minute.
public struct SplitDraft: Equatable, Sendable {
    public let span: DateInterval
    /// Whole minutes from the start of the span to each divider, ascending.
    public private(set) var minutes: [Int] = [0]
    /// The activity field of each part.
    public var parts: [CheckInList]

    /// Two parts divided in the middle.
    public init(span: DateInterval, first: CheckInList, second: CheckInList) {
        self.span = span
        parts = [first, second]
        minutes[0] = clamped(Int(span.duration / 60) / 2, at: 0)
    }

    public var dividers: [Date] {
        minutes.map { span.start + TimeInterval($0 * 60) }
    }

    public var intervals: [DateInterval] {
        let bounds = [span.start] + dividers + [span.end]
        return zip(bounds, bounds.dropFirst()).map { DateInterval(start: $0, end: $1) }
    }

    /// Snaps to the nearest whole minute.
    public mutating func moveDivider(_ index: Int, to date: Date) {
        minutes[index] = clamped(Int((date.timeIntervalSince(span.start) / 60).rounded()), at: index)
    }

    public mutating func moveDivider(_ index: Int, by offset: Int) {
        minutes[index] = clamped(minutes[index] + offset, at: index)
    }

    public var canAddPart: Bool { lastPart >= 120 }

    /// Halves the last part, the new part follows it.
    public mutating func addPart(_ list: CheckInList) {
        guard canAddPart, let last = minutes.last else { return }
        minutes.append(last + Int(lastPart / 60) / 2)
        parts.append(list)
    }

    /// The activity of every part, nil while one has none.
    public var choices: [CheckInList.Choice]? {
        let choices = parts.compactMap(\.choice)
        return choices.count == parts.count ? choices : nil
    }

    private var lastPart: TimeInterval {
        span.duration - TimeInterval((minutes.last ?? 0) * 60)
    }

    /// Keeps a minute for the parts on both sides.
    private func clamped(_ minute: Int, at index: Int) -> Int {
        let lower = index == 0 ? 1 : minutes[index - 1] + 1
        let upper = index == minutes.count - 1 ? Int((span.duration - 60) / 60) : minutes[index + 1] - 1
        return min(max(minute, lower), upper)
    }
}
