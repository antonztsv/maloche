import Foundation

/// The system deactivates an app without a Dock icon when its policy changes to accessory (1 ms after) or its status
/// item is clicked (60 ms before the session); a resign that close to the cause counts as caused by it.
public enum SystemDeactivation {
    public static let tolerance: TimeInterval = 0.5

    public static func caused(by cause: Date?, resignedAt: Date?) -> Bool {
        guard let cause, let resignedAt else { return false }
        return abs(resignedAt.timeIntervalSince(cause)) <= tolerance
    }
}
