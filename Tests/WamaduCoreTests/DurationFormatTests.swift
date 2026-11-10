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

    @Test func spokenDurationsNameHoursAndMinutes() {
        #expect(DurationFormat.spoken(7 * 3600 + 45 * 60, locale: english) == "7 hours 45 minutes")
        #expect(DurationFormat.spoken(3600 + 60, locale: english) == "1 hour 1 minute")
        #expect(DurationFormat.spoken(8 * 3600, locale: english) == "8 hours")
        #expect(DurationFormat.spoken(30 * 60, locale: english) == "30 minutes")
        #expect(DurationFormat.spoken(0, locale: english) == "0 minutes")
    }

    @Test func spokenDurationsRoundLikeTheShownOnes() {
        #expect(DurationFormat.spoken(7 * 3600 + 44 * 60 + 30, locale: english) == "7 hours 45 minutes")
        #expect(DurationFormat.spoken(25 * 3600 + 59 * 60 + 40, locale: english) == "26 hours")
    }
}
