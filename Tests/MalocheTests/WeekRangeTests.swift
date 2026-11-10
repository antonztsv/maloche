import Foundation
import Testing

@testable import Maloche

/// The week beside the dashboard title names its month once, in the order of the locale.
@Suite struct WeekRangeTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func range(_ start: Date, _ last: Date, _ locale: String) -> String {
        DashboardView.weekRange(from: start, to: last, calendar: calendar, locale: Locale(identifier: locale))
    }

    @Test func aWeekWithinOneMonth() {
        #expect(range(day(11, 2), day(11, 8), "en_US") == "November 2 to 8")
        #expect(range(day(11, 2), day(11, 8), "en_DE") == "2. to 8. November")
        #expect(range(day(11, 2), day(11, 8), "de_DE") == "2. to 8. November")
    }

    @Test func aWeekAcrossTwoMonths() {
        #expect(range(day(10, 26), day(11, 1), "en_US") == "October 26 to November 1")
        #expect(range(day(10, 26), day(11, 1), "de_DE") == "26. Oktober to 1. November")
    }
}
