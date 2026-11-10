import Foundation

public enum DurationFormat {
    /// "7:45", rounded to the nearest minute, hours not capped at 24.
    public static func hoursMinutes(_ duration: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(duration).formatted(
            .time(pattern: .hourMinute(padHourToLength: 1, roundSeconds: .toNearestOrAwayFromZero)).locale(locale))
    }

    /// "7 hours 45 minutes" for VoiceOver, rounded to the nearest minute like `hoursMinutes`.
    public static func spoken(_ duration: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        let minutes = Int((max(duration, 0) / 60).rounded(.toNearestOrAwayFromZero))
        func format(_ seconds: Int, _ unit: Duration.UnitsFormatStyle.Unit) -> String {
            Duration.seconds(seconds).formatted(.units(allowed: [unit], width: .wide).locale(locale))
        }
        let hours = format(minutes / 60 * 3600, .hours)
        let rest = format(minutes % 60 * 60, .minutes)
        switch (minutes / 60, minutes % 60) {
        case (0, _): return rest
        case (_, 0): return hours
        default: return "\(hours) \(rest)"
        }
    }
}
