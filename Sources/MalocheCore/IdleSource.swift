import Foundation

public protocol IdleSource: Sendable {
    /// Seconds since the last keyboard or mouse input in this login session.
    var secondsSinceLastInput: TimeInterval { get }
}
