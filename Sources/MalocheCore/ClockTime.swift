import Foundation

/// A clock time typed into the start or end field of a span.
public enum ClockTime {
    /// "16:30", "16.30", "1630", "16" or "4:30 pm" on the calendar day of `reference`, nil for anything else.
    /// On a 12 hour clock an hour without AM or PM takes the half of the day nearest to `reference`.
    public static func date(from text: String, onDayOf reference: Date, calendar: Calendar, locale: Locale) -> Date? {
        var calendar = calendar
        calendar.locale = locale
        var text = text.trimmingCharacters(in: .whitespaces).lowercased()
        var pm: Bool?
        let markers = [
            (calendar.amSymbol, false), (calendar.pmSymbol, true), ("am", false), ("pm", true), ("a", false),
            ("p", true),
        ]
        for (marker, isPM) in markers {
            let marker = marker.lowercased()
            guard !marker.isEmpty, text.hasSuffix(marker) else { continue }
            text = text.dropLast(marker.count).trimmingCharacters(in: .whitespaces)
            pm = isPM
            break
        }
        guard let (hour, minute) = hourAndMinute(text), minute < 60 else { return nil }
        let referenceMinutes =
            calendar.component(.hour, from: reference) * 60 + calendar.component(.minute, from: reference)
        let hours: [Int]
        if let pm {
            guard (1...12).contains(hour) else { return nil }
            hours = [hour % 12 + (pm ? 12 : 0)]
        } else if [.oneToTwelve, .zeroToEleven].contains(locale.hourCycle), (1...12).contains(hour) {
            hours = [hour % 12, hour % 12 + 12]
        } else {
            guard hour < 24 else { return nil }
            hours = [hour]
        }
        let nearest = hours.min { abs($0 * 60 + minute - referenceMinutes) < abs($1 * 60 + minute - referenceMinutes) }!
        return calendar.date(bySettingHour: nearest, minute: minute, second: 0, of: reference)
    }

    private static func hourAndMinute(_ text: String) -> (Int, Int)? {
        let parts = text.split(omittingEmptySubsequences: false) { $0 == ":" || $0 == "." }
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }) else { return nil }
        switch (parts.count, parts.first?.count ?? 0) {
        case (1, 1...2): return (Int(parts[0])!, 0)
        case (1, 3...4): return (Int(parts[0].dropLast(2))!, Int(parts[0].suffix(2))!)
        case (2, 1...2) where parts[1].count == 2: return (Int(parts[0])!, Int(parts[1])!)
        default: return nil
        }
    }
}
