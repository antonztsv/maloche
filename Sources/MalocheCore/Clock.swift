import Foundation

public protocol WallClock: Sendable {
    var now: Date { get }
}

public struct SystemWallClock: WallClock {
    public init() {}
    public var now: Date { Date() }
}
