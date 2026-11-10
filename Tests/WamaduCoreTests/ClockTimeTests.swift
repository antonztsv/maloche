import Foundation
import Testing

@testable import WamaduCore

/// S10: a clock time typed into the start or end field of a span.
@Suite struct ClockTimeTests {
    private let german = Locale(identifier: "de_DE")
    private let american = Locale(identifier: "en_US")

    private func parse(_ text: String, near reference: String = "10:00", locale: Locale? = nil) -> Date? {
        ClockTime.date(
            from: text, onDayOf: Fixture.at(reference), calendar: Fixture.berlin, locale: locale ?? german)
    }

    @Test func readsTheTwentyFourHourClockWithOrWithoutSeparator() {
        #expect(parse("16:30") == Fixture.at("16:30"))
        #expect(parse("9:05") == Fixture.at("09:05"))
        #expect(parse("09.05") == Fixture.at("09:05"))
        #expect(parse("905") == Fixture.at("09:05"))
        #expect(parse("1630") == Fixture.at("16:30"))
        #expect(parse("16") == Fixture.at("16:00"))
        #expect(parse(" 7:15 ") == Fixture.at("07:15"))
        #expect(parse("0:00") == Fixture.at("00:00"))
    }

    @Test func refusesWhatIsNoClockTime() {
        for text in ["", "abc", "24:00", "12:60", "12:3", "1:2:3", "12345", "-1", "12:", ":30", "4 xm"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func readsAmAndPmInAnyLocale() {
        #expect(parse("4:30 PM", locale: american) == Fixture.at("16:30"))
        #expect(parse("4:30\u{202F}PM", locale: american) == Fixture.at("16:30"))
        #expect(parse("4:30pm", locale: american) == Fixture.at("16:30"))
        #expect(parse("4p", locale: american) == Fixture.at("16:00"))
        #expect(parse("12 AM", locale: american) == Fixture.at("00:00"))
        #expect(parse("12:15 PM", locale: american) == Fixture.at("12:15"))
        #expect(parse("4:30 pm") == Fixture.at("16:30"))
        #expect(parse("13:00 PM", locale: american) == nil)
        #expect(parse("0:30 AM", locale: american) == nil)
    }

    @Test func onATwelveHourClockAnHourWithoutAmOrPmTakesTheHalfOfTheDayNearestTheShownTime() {
        #expect(parse("4:30", near: "15:00", locale: american) == Fixture.at("16:30"))
        #expect(parse("11", near: "10:00", locale: american) == Fixture.at("11:00"))
        #expect(parse("12", near: "10:00", locale: american) == Fixture.at("12:00"))
        #expect(parse("16:30", near: "10:00", locale: american) == Fixture.at("16:30"))
        #expect(parse("4:30", near: "15:00") == Fixture.at("04:30"))
    }

    @Test func staysOnTheDayOfTheShownTimeAcrossMidnightAndDaylightSaving() {
        #expect(parse("0:45", near: "2026-11-10 00:30") == Fixture.at("2026-11-10 00:45"))
        #expect(parse("12:00", near: "2026-10-25 09:00") == Fixture.at("2026-10-25 12:00"))
        #expect(parse("10:00", near: "2026-03-29 18:00") == Fixture.at("2026-03-29 10:00"))
    }
}
