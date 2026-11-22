import Foundation
import Testing

@testable import MalocheCore

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

    @Test func spokenDurationsUnderAMinuteNameSeconds() {
        #expect(DurationFormat.spoken(6, locale: english) == "6 seconds")
        #expect(DurationFormat.spoken(59, locale: english) == "59 seconds")
        #expect(DurationFormat.spoken(60, locale: english) == "1 minute")
        #expect(DurationFormat.spoken(61, locale: english) == "1 minute")
        #expect(DurationFormat.spoken(0, locale: english) == "0 minutes")
        #expect(DurationFormat.spoken(6, locale: Locale(identifier: "de_DE")) == "6 Sekunden")
    }

    @Test func spokenDurationsRoundLikeTheShownOnes() {
        #expect(DurationFormat.spoken(7 * 3600 + 44 * 60 + 30, locale: english) == "7 hours 45 minutes")
        #expect(DurationFormat.spoken(25 * 3600 + 59 * 60 + 40, locale: english) == "26 hours")
    }
}
