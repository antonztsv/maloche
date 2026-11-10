import Foundation

public enum DurationText {
    /// A span under an hour as "15 minutes", from an hour on as "1:45", nil under a minute; rounded down to minutes.
    public static func span(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String? {
        let minutes = Int(max(seconds, 0) / 60)
        guard minutes > 0 else { return nil }
        let duration = Duration.seconds(minutes * 60)
        if minutes < 60 {
            return duration.formatted(.units(allowed: [.minutes], width: .wide).locale(locale))
        }
        return duration.formatted(.time(pattern: .hourMinute).locale(locale))
    }
}
