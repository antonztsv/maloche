import Foundation
import Testing

@testable import MalocheCore

/// The dashboard figures with rounding: lists, customer totals, work and break per day and period.
@Suite struct RoundedSummaryTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let acme = Customer(id: 1, name: "Acme", colorIndex: 0)
    private let relaunch = Project(id: 1, name: "Relaunch", customerId: 1)
    private let writing = Activity(id: 1, name: "Writing")
    private let review = Activity(id: 2, name: "Code Review", projectId: 1)
    private let breakActivity = Activity(id: 3, name: "Break", kind: .break)

    private func local(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    private func block(_ activity: Activity, _ day: Int, _ hour: Int, _ minute: Int, to end: Date) -> Block {
        Block(activityId: activity.id!, startedAt: local(day, hour, minute), endedAt: end, source: .checkIn)
    }

    /// Monday: Writing 4 and 4 min, Code Review 22:30 min, Break 8 min. Tuesday: Writing 4 and 4 min.
    private var blocks: [Block] {
        [
            block(writing, 9, 9, 0, to: local(9, 9, 4)),
            block(writing, 9, 10, 0, to: local(9, 10, 4)),
            block(review, 9, 11, 0, to: local(9, 11, 22, 30)),
            block(breakActivity, 9, 12, 0, to: local(9, 12, 8)),
            block(writing, 10, 9, 0, to: local(10, 9, 4)),
            block(writing, 10, 10, 0, to: local(10, 10, 4)),
        ]
    }

    private func summary(_ kind: PeriodKind, _ blocks: [Block]? = nil) -> PeriodSummary {
        Reports.summary(
            of: Period(kind, containing: local(9, 12), calendar: calendar), blocks: blocks ?? self.blocks,
            activities: [writing, review, breakActivity], projects: [relaunch], customers: [acme], calendar: calendar)
    }

    private func minutes(_ seconds: TimeInterval?) -> Double? { seconds.map { $0 / 60 } }

    @Test func withoutAStepEverythingStaysExact() {
        for kind in [PeriodKind.day, .week, .month] {
            for step in [nil, 0] {
                let rounding = RoundingSettings(stepMinutes: step, mode: .up, level: .entry)
                #expect(summary(kind).rounded(by: rounding) == summary(kind))
            }
        }
    }

    @Test(
        arguments: [
            // level, week work, week break, Writing, Code Review, Monday work, Tuesday work
            (RoundingSettings.Level.entry, 30, 15, 0, 30, 30, 0),
            (.dayAndActivity, 60, 15, 30, 30, 45, 15),
            (.period, 45, 15, 15, 30, 45, 15),
        ] as [(RoundingSettings.Level, Double, Double, Double, Double, Double, Double)])
    func weekFiguresAtEachLevel(
        level: RoundingSettings.Level, work: Double, breaks: Double, writingTotal: Double, reviewTotal: Double,
        monday: Double, tuesday: Double
    ) {
        let exact = summary(.week)
        let rounded = exact.rounded(by: RoundingSettings(stepMinutes: 15, mode: .nearest, level: level))
        #expect(minutes(rounded.work) == work)
        #expect(minutes(rounded.breaks) == breaks)
        let byActivity = Dictionary(uniqueKeysWithValues: rounded.activities.map { ($0.activity.id!, $0.duration) })
        #expect(minutes(byActivity[1]) == writingTotal)
        #expect(minutes(byActivity[2]) == reviewTotal)
        let customers = Dictionary(uniqueKeysWithValues: rounded.customers.map { ($0.customer?.id, $0.duration) })
        #expect(minutes(customers[1]) == reviewTotal)
        #expect(minutes(customers[nil as Int64?]) == writingTotal)
        let acme = rounded.customers.first { $0.customer?.id == 1 }
        #expect(minutes(acme?.projects.first?.duration) == reviewTotal)
        #expect(rounded.customers.reduce(0) { $0 + $1.duration } == rounded.work)

        #expect(minutes(rounded.days[0].work) == monday)
        #expect(minutes(rounded.days[0].breaks) == 15)
        #expect(minutes(rounded.days[0].workByCustomer[1]) == 30)
        #expect(minutes(rounded.days[0].workByCustomer[nil] ?? 0) == monday - 30)
        #expect(minutes(rounded.days[1].work) == tuesday)
        #expect(rounded.days[1].breaks == 0)
        #expect(rounded.days.dropFirst(2).allSatisfy { $0.work == 0 && $0.breaks == 0 })

        #expect(rounded.days.map(\.start) == exact.days.map(\.start))
        #expect(rounded.days.map(\.end) == exact.days.map(\.end))
        #expect(rounded.entries == exact.entries)
    }

    @Test func dayFiguresPerDayAndActivity() {
        let monday = Reports.summary(
            of: Period(.day, containing: local(9, 12), calendar: calendar), blocks: blocks,
            activities: [writing, review, breakActivity], projects: [relaunch], customers: [acme], calendar: calendar)
        let rounded = monday.rounded(by: RoundingSettings(stepMinutes: 15, mode: .up, level: .dayAndActivity))
        #expect(minutes(rounded.work) == 45)
        #expect(minutes(rounded.breaks) == 15)
        #expect(minutes(rounded.days[0].work) == 45)
        #expect(rounded.activities.map { minutes($0.duration) } == [30, 15])
    }

    @Test func longestFirstAfterRounding() {
        let blocks = [
            block(writing, 9, 9, 0, to: local(9, 9, 20)),
            block(review, 9, 10, 0, to: local(9, 10, 8)),
            block(review, 9, 11, 0, to: local(9, 11, 8)),
        ]
        let exact = summary(.day, blocks)
        #expect(exact.activities.map(\.activity.id) == [1, 2])
        let rounded = exact.rounded(by: RoundingSettings(stepMinutes: 15, mode: .nearest, level: .entry))
        #expect(rounded.activities.map(\.activity.id) == [2, 1])
        #expect(rounded.activities.map { minutes($0.duration) } == [30, 15])
        #expect(rounded.customers.map(\.customer?.id) == [1, nil])
    }

    @Test func aDayRoundedToNothingDrawsNoCustomerPart() {
        let rounded = summary(.week).rounded(by: RoundingSettings(stepMinutes: 15, mode: .nearest, level: .entry))
        #expect(rounded.days[1].workByCustomer.isEmpty)
        #expect(rounded.days[0].workByCustomer.keys.sorted { ($0 ?? 0) < ($1 ?? 0) } == [1])
        #expect(rounded.daysWithWork == 1)
    }
}
