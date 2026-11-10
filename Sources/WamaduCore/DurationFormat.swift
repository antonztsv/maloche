import Foundation

public enum DurationFormat {
    /// "7:45", rounded to the nearest minute, hours not capped at 24.
    public static func hoursMinutes(_ duration: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(duration).formatted(
            .time(pattern: .hourMinute(padHourToLength: 1, roundSeconds: .toNearestOrAwayFromZero)).locale(locale))
    }
}
