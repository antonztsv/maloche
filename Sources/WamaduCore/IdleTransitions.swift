import Foundation

public protocol IdleSource: Sendable {
    /// Seconds since the last keyboard or mouse input in this login session.
    var secondsSinceLastInput: TimeInterval { get }
}

public enum PresenceEvent: Equatable, Sendable {
    case away(since: Date)
    case back(at: Date)
}

/// Turns periodic idle-time samples into away and back events. Away starts with the last input.
public struct IdleTransitions: Sendable {
    public let threshold: TimeInterval
    public private(set) var isAway = false

    public init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    public mutating func update(idleSeconds: TimeInterval, now: Date) -> PresenceEvent? {
        if !isAway, idleSeconds >= threshold {
            isAway = true
            return .away(since: now - idleSeconds)
        }
        if isAway, idleSeconds < threshold {
            isAway = false
            return .back(at: now - idleSeconds)
        }
        return nil
    }
}
