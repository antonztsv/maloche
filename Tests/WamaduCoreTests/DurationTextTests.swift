import Foundation
import Testing

@testable import WamaduCore

@Suite struct DurationTextTests {
    private let english = Locale(identifier: "en_US")

    @Test func underAMinuteHasNoText() {
        #expect(DurationText.span(0, locale: english) == nil)
        #expect(DurationText.span(59, locale: english) == nil)
    }

    @Test func underAnHourInWholeMinutes() {
        #expect(DurationText.span(60, locale: english) == "1 minute")
        #expect(DurationText.span(15 * 60 + 40, locale: english) == "15 minutes")
        #expect(DurationText.span(59 * 60 + 59, locale: english) == "59 minutes")
    }

    @Test func fromAnHourAsHoursAndMinutes() {
        #expect(DurationText.span(3600, locale: english) == "1:00")
        #expect(DurationText.span(105 * 60 + 30, locale: english) == "1:45")
        #expect(DurationText.span(10 * 3600 + 5 * 60, locale: english) == "10:05")
    }

    @Test func spokenSpansNameHoursAndMinutesRoundedDown() {
        #expect(DurationText.spokenSpan(59, locale: english) == nil)
        #expect(DurationText.spokenSpan(15 * 60 + 40, locale: english) == "15 minutes")
        #expect(DurationText.spokenSpan(105 * 60 + 30, locale: english) == "1 hour 45 minutes")
    }
}
