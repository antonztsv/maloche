import Foundation
import Testing

@testable import WamaduCore

@Suite struct DurationFormatTests {
    private let english = Locale(identifier: "en_US")

    @Test func hoursAndMinutesRoundToTheNearestMinute() {
        #expect(DurationFormat.hoursMinutes(7 * 3600 + 44 * 60 + 30, locale: english) == "7:45")
        #expect(DurationFormat.hoursMinutes(7 * 3600 + 44 * 60 + 29, locale: english) == "7:44")
    }

    @Test func shortAndLongDurationsKeepHoursAndMinutes() {
        #expect(DurationFormat.hoursMinutes(45 * 60, locale: english) == "0:45")
        #expect(DurationFormat.hoursMinutes(25 * 3600, locale: english) == "25:00")
    }
}
