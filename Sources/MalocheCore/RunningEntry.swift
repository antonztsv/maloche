import Foundation

/// The block being booked right now: its activity and since when.
public struct RunningEntry: Equatable, Sendable {
    public var activityId: Int64
    public var since: Date

    /// A drawn entry of the activity that reaches the running block.
    public func contains(activityId: Int64, interval: DateInterval) -> Bool {
        activityId == self.activityId && since <= interval.end
    }
}
