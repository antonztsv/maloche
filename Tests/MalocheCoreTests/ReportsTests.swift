import Foundation
import Testing

@testable import MalocheCore

@Suite struct ReportsTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let acme = Customer(id: 1, name: "Acme", colorIndex: 0)
    private let globex = Customer(id: 2, name: "Globex", colorIndex: 1)
    private let website = Project(id: 10, name: "Website", customerId: 1)
    private let internalProject = Project(id: 11, name: "Internal", customerId: nil)
    private let writing = Activity(id: 100, name: "Writing", projectId: 10)
    private let review = Activity(id: 101, name: "Code Review", customerId: 2)
    private let reading = Activity(id: 102, name: "Reading")
    private let planning = Activity(id: 103, name: "Planning", projectId: 11)
    private let breakActivity = Activity(id: 900, name: "Break", kind: .break)
    private let privateActivity = Activity(id: 901, name: "Private", kind: .private)

    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func block(_ activity: Activity, _ from: Date, _ to: Date) -> Block {
        Block(activityId: activity.id!, startedAt: from, endedAt: to, source: .checkIn)
    }

    private func summary(_ period: Period, _ blocks: [Block], activities: [Activity]? = nil) -> PeriodSummary {
        Reports.summary(
            of: period, blocks: blocks,
            activities: activities ?? [writing, review, reading, planning, breakActivity, privateActivity],
            projects: [website, internalProject], customers: [acme, globex], calendar: calendar)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Period {
        Period(.day, containing: local(year, month, day, 12), calendar: calendar)
    }

    // MARK: Periods

    @Test func dayRunsFromLocalMidnightToMidnightAndPages() {
        let period = day(2026, 11, 9)
        #expect(period.interval == DateInterval(start: local(2026, 11, 9), end: local(2026, 11, 10)))
        #expect(period.next(calendar: calendar).interval.start == local(2026, 11, 10))
        #expect(period.previous(calendar: calendar).interval.start == local(2026, 11, 8))
        #expect(period.previous(calendar: calendar).kind == .day)
    }

    @Test func springForwardDayHas23Hours() {
        let period = day(2026, 3, 29)
        #expect(period.interval == DateInterval(start: utc(2026, 3, 28, 23), end: utc(2026, 3, 29, 22)))
        #expect(period.interval.duration == 23 * 3600)
        #expect(period.next(calendar: calendar).interval.duration == 24 * 3600)
    }

    @Test func fallBackDayHas25Hours() {
        let period = day(2026, 10, 25)
        #expect(period.interval == DateInterval(start: utc(2026, 10, 24, 22), end: utc(2026, 10, 25, 23)))
        #expect(period.interval.duration == 25 * 3600)
        #expect(period.next(calendar: calendar).previous(calendar: calendar) == period)
    }

    @Test func weekStartsOnTheCalendarsFirstWeekday() {
        let wednesday = local(2026, 11, 11, 12)
        let week = Period(.week, containing: wednesday, calendar: calendar)
        #expect(week.interval == DateInterval(start: local(2026, 11, 9), end: local(2026, 11, 16)))
        #expect(week.days(calendar: calendar).count == 7)
        #expect(week.next(calendar: calendar).interval.start == local(2026, 11, 16))
        #expect(week.previous(calendar: calendar).interval.start == local(2026, 11, 2))

        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let usWeek = Period(.week, containing: wednesday, calendar: sundayFirst)
        #expect(usWeek.interval == DateInterval(start: local(2026, 11, 8), end: local(2026, 11, 15)))
    }

    @Test func weekAcrossFallBackHas169Hours() {
        let week = Period(.week, containing: local(2026, 10, 25, 12), calendar: calendar)
        #expect(week.interval == DateInterval(start: local(2026, 10, 19), end: local(2026, 10, 26)))
        #expect(week.interval.duration == 7 * 24 * 3600 + 3600)
        let longDays: [TimeInterval] = week.days(calendar: calendar).map(\.duration).filter { $0 != 86400 }
        #expect(longDays == [90000])
    }

    @Test func monthPagesAcrossYearAndDst() {
        let january = Period(.month, containing: local(2026, 1, 15), calendar: calendar)
        #expect(january.interval == DateInterval(start: local(2026, 1, 1), end: local(2026, 2, 1)))
        let december = january.previous(calendar: calendar)
        #expect(december.interval == DateInterval(start: local(2025, 12, 1), end: local(2026, 1, 1)))
        let february = january.next(calendar: calendar)
        #expect(february.days(calendar: calendar).count == 28)
        let march = february.next(calendar: calendar)
        #expect(march.days(calendar: calendar).count == 31)
        #expect(march.interval.duration == 31 * 24 * 3600 - 3600)
    }

    // MARK: Summaries

    @Test func simpleDay() {
        let blocks = [
            block(writing, local(2026, 11, 9, 9), local(2026, 11, 9, 10, 30)),
            block(review, local(2026, 11, 9, 10, 30), local(2026, 11, 9, 12)),
            block(breakActivity, local(2026, 11, 9, 12), local(2026, 11, 9, 12, 30)),
            block(reading, local(2026, 11, 9, 12, 30), local(2026, 11, 9, 13)),
        ]
        let result = summary(day(2026, 11, 9), blocks)
        #expect(result.work == 12600)
        #expect(result.breaks == 1800)
        #expect(result.days.count == 1)
        #expect(result.days[0].start == local(2026, 11, 9, 9))
        #expect(result.days[0].end == local(2026, 11, 9, 13))
        #expect(result.daysWithWork == 1)
        #expect(result.averageWorkPerDay == 12600)
        #expect(
            result.activities == [
                ActivityTotal(activity: review, duration: 5400),
                ActivityTotal(activity: writing, duration: 5400),
                ActivityTotal(activity: reading, duration: 1800),
            ])
    }

    @Test func blockAcrossMidnightIsSplitIntoTwoDays() {
        let blocks = [block(writing, local(2026, 11, 9, 22), local(2026, 11, 10, 2))]
        let week = summary(Period(.week, containing: local(2026, 11, 9), calendar: calendar), blocks)
        #expect(week.work == 4 * 3600)
        #expect(week.days[0].work == 2 * 3600)
        #expect(week.days[0].start == local(2026, 11, 9, 22))
        #expect(week.days[0].end == local(2026, 11, 10))
        #expect(week.days[1].work == 2 * 3600)
        #expect(week.days[1].start == local(2026, 11, 10))
        #expect(week.days[1].end == local(2026, 11, 10, 2))
        #expect(week.daysWithWork == 2)
        #expect(week.averageWorkPerDay == 2 * 3600)
        #expect(
            week.entries == [
                ReportEntry(day: local(2026, 11, 9), activityId: 100, duration: 7200),
                ReportEntry(day: local(2026, 11, 10), activityId: 100, duration: 7200),
            ])

        #expect(summary(day(2026, 11, 9), blocks).work == 2 * 3600)
    }

    @Test func springForwardBlockAcrossTheChangeCountsRealTime() {
        let blocks = [block(writing, local(2026, 3, 29, 1), local(2026, 3, 29, 4))]
        #expect(summary(day(2026, 3, 29), blocks).work == 2 * 3600)

        let wholeDay = [block(writing, local(2026, 3, 28, 20), local(2026, 3, 30, 4))]
        #expect(summary(day(2026, 3, 29), wholeDay).work == 23 * 3600)
    }

    @Test func fallBackBlockAcrossTheChangeCountsRealTime() {
        let blocks = [block(writing, utc(2026, 10, 24, 23), utc(2026, 10, 25, 3))]
        let result = summary(day(2026, 10, 25), blocks)
        #expect(result.work == 4 * 3600)
        #expect(result.days[0].start == local(2026, 10, 25, 1))
        #expect(result.days[0].end == local(2026, 10, 25, 4))

        let wholeDay = [block(writing, local(2026, 10, 24, 20), local(2026, 10, 26, 4))]
        #expect(summary(day(2026, 10, 25), wholeDay).work == 25 * 3600)
    }

    @Test func blocksCrossingTheMonthBoundaryAreClipped() {
        let blocks = [block(writing, local(2026, 1, 31, 23), local(2026, 2, 1, 1))]
        let february = Period(.month, containing: local(2026, 2, 10), calendar: calendar)
        #expect(summary(february, blocks).work == 3600)
        #expect(summary(february.previous(calendar: calendar), blocks).work == 3600)
        #expect(summary(february.next(calendar: calendar), blocks).work == 0)
    }

    @Test func breakIsSeparateAndPrivateIsNeither() {
        let blocks = [
            block(privateActivity, local(2026, 11, 9, 7), local(2026, 11, 9, 8)),
            block(writing, local(2026, 11, 9, 9), local(2026, 11, 9, 10, 30)),
            block(breakActivity, local(2026, 11, 9, 10, 30), local(2026, 11, 9, 10, 45)),
            block(reading, local(2026, 11, 9, 10, 45), local(2026, 11, 9, 11, 15)),
            block(privateActivity, local(2026, 11, 9, 18), local(2026, 11, 9, 19)),
        ]
        let result = summary(day(2026, 11, 9), blocks)
        #expect(result.work == 7200)
        #expect(result.breaks == 900)
        #expect(result.days[0].start == local(2026, 11, 9, 9))
        #expect(result.days[0].end == local(2026, 11, 9, 11, 15))
        #expect(result.activities.map(\.activity.name) == ["Writing", "Reading"])
        #expect(result.customers.map(\.duration) == [5400, 1800])
        #expect(result.days[0].workByCustomer == [1: 5400, nil: 1800])
        #expect(!result.entries.contains { $0.activityId == 901 })
        #expect(result.entries.contains { $0.activityId == 900 })
    }

    @Test func breakOnlyDayHasNoWork() {
        let blocks = [block(breakActivity, local(2026, 11, 10, 12), local(2026, 11, 10, 13))]
        let week = summary(Period(.week, containing: local(2026, 11, 10), calendar: calendar), blocks)
        #expect(week.breaks == 3600)
        #expect(week.daysWithWork == 0)
        #expect(week.averageWorkPerDay == 0)
        #expect(week.days[1].start == local(2026, 11, 10, 12))
        #expect(week.activities.isEmpty)
        #expect(week.customers.isEmpty)
    }

    @Test func emptyPeriodGivesZeros() {
        let result = summary(Period(.month, containing: local(2026, 11, 9), calendar: calendar), [])
        #expect(result.work == 0)
        #expect(result.breaks == 0)
        #expect(result.days.count == 30)
        #expect(result.days.allSatisfy { $0.work == 0 && $0.breaks == 0 && $0.start == nil && $0.end == nil })
        #expect(result.days.allSatisfy { $0.workByCustomer.isEmpty })
        #expect(result.daysWithWork == 0)
        #expect(result.averageWorkPerDay == 0)
        #expect(result.activities.isEmpty)
        #expect(result.customers.isEmpty)
        #expect(result.entries.isEmpty)
    }

    @Test func archivedActivitiesAreStillCounted() {
        var archived = writing
        archived.archived = true
        let blocks = [block(archived, local(2026, 11, 9, 9), local(2026, 11, 9, 10))]
        let result = summary(day(2026, 11, 9), blocks, activities: [archived])
        #expect(result.work == 3600)
        #expect(result.activities == [ActivityTotal(activity: archived, duration: 3600)])
    }

    @Test func groupsByCustomerThenProjectThenActivity() {
        let blocks = [
            block(writing, local(2026, 11, 9, 8), local(2026, 11, 9, 10)),
            block(review, local(2026, 11, 9, 10), local(2026, 11, 9, 11)),
            block(reading, local(2026, 11, 9, 11), local(2026, 11, 9, 11, 30)),
            block(planning, local(2026, 11, 9, 11, 30), local(2026, 11, 9, 12, 15)),
        ]
        let result = summary(day(2026, 11, 9), blocks)
        #expect(
            result.customers == [
                CustomerTotal(
                    customer: acme, duration: 7200,
                    projects: [
                        ProjectTotal(
                            project: website, duration: 7200,
                            activities: [ActivityTotal(activity: writing, duration: 7200)])
                    ]),
                CustomerTotal(
                    customer: nil, duration: 4500,
                    projects: [
                        ProjectTotal(
                            project: internalProject, duration: 2700,
                            activities: [ActivityTotal(activity: planning, duration: 2700)]),
                        ProjectTotal(
                            project: nil, duration: 1800,
                            activities: [ActivityTotal(activity: reading, duration: 1800)]),
                    ]),
                CustomerTotal(
                    customer: globex, duration: 3600,
                    projects: [
                        ProjectTotal(
                            project: nil, duration: 3600,
                            activities: [ActivityTotal(activity: review, duration: 3600)])
                    ]),
            ])
    }

    @Test func weekHasWorkPerDayPerCustomer() {
        let blocks = [
            block(writing, local(2026, 11, 9, 9), local(2026, 11, 9, 11)),
            block(review, local(2026, 11, 9, 11), local(2026, 11, 9, 12)),
            block(writing, local(2026, 11, 10, 9), local(2026, 11, 10, 10)),
            block(reading, local(2026, 11, 10, 10), local(2026, 11, 10, 10, 30)),
        ]
        let week = summary(Period(.week, containing: local(2026, 11, 12), calendar: calendar), blocks)
        #expect(week.days[0].workByCustomer == [1: 7200, 2: 3600])
        #expect(week.days[1].workByCustomer == [1: 3600, nil: 1800])
        #expect(week.days[2].workByCustomer.isEmpty)
        #expect(week.daysWithWork == 2)
        #expect(week.averageWorkPerDay == 16200 / 2)
    }

    // MARK: Week and month

    @Test func weekStacksFollowTheCustomerTotalsWithoutBreaks() {
        let blocks = [
            block(review, local(2026, 11, 9, 8), local(2026, 11, 9, 9)),
            block(writing, local(2026, 11, 9, 9), local(2026, 11, 9, 11)),
            block(breakActivity, local(2026, 11, 9, 11), local(2026, 11, 9, 12)),
            block(reading, local(2026, 11, 9, 12), local(2026, 11, 9, 12, 30)),
            block(privateActivity, local(2026, 11, 9, 18), local(2026, 11, 9, 22)),
            block(planning, local(2026, 11, 10, 8), local(2026, 11, 10, 10)),
            block(review, local(2026, 11, 10, 10), local(2026, 11, 10, 10, 30)),
        ]
        let week = summary(Period(.week, containing: local(2026, 11, 9), calendar: calendar), blocks)
        #expect(week.customers.map(\.customer?.id) == [nil, 1, 2])
        #expect(
            week.stack(of: week.days[0]) == [
                CustomerWork(customer: nil, duration: 1800), CustomerWork(customer: acme, duration: 7200),
                CustomerWork(customer: globex, duration: 3600),
            ])
        #expect(
            week.stack(of: week.days[1]) == [
                CustomerWork(customer: nil, duration: 7200), CustomerWork(customer: globex, duration: 1800),
            ])
        #expect(week.stack(of: week.days[2]).isEmpty)
        #expect(week.days.map(\.work) == [12600, 9000, 0, 0, 0, 0, 0] as [TimeInterval])
        #expect(week.share(of: week.days[0]) == 1)
        #expect(week.share(of: week.days[1]) == 9000.0 / 12600)
        #expect(week.share(of: week.days[2]) == 0)
        #expect(week.breaks == 3600)
        #expect(week.daysWithWork == 2)
        #expect(week.averageWorkPerDay == 21600 / 2)
    }

    @Test func weekAcrossFallBackCountsTheLongDayAndSplitsAtMidnight() {
        let blocks = [
            block(writing, local(2026, 10, 23, 9), local(2026, 10, 23, 17)),
            block(writing, local(2026, 10, 24, 20), local(2026, 10, 26, 4)),
        ]
        let week = summary(Period(.week, containing: local(2026, 10, 25, 12), calendar: calendar), blocks)
        let hours: [TimeInterval] = [0, 0, 0, 0, 8, 4, 25]
        #expect(week.days.map(\.work) == hours.map { $0 * 3600 })
        #expect(week.stack(of: week.days[6]) == [CustomerWork(customer: acme, duration: 25 * 3600)])
        #expect(week.stack(of: week.days[5]) == [CustomerWork(customer: acme, duration: 4 * 3600)])
        #expect(week.share(of: week.days[6]) == 1)
        #expect(week.share(of: week.days[4]) == 8.0 / 25)
        #expect(week.daysWithWork == 3)
        #expect(week.averageWorkPerDay == 37 * 3600 / 3)
    }

    @Test func emptyWeekHasNoStacksAndNoShares() {
        let week = summary(Period(.week, containing: local(2026, 11, 9), calendar: calendar), [])
        #expect(week.days.allSatisfy { week.stack(of: $0).isEmpty && week.share(of: $0) == 0 })
    }

    @Test func monthGridStartsMidWeekOnTheCalendarsFirstWeekday() {
        let blocks = [
            block(writing, local(2026, 10, 1, 9), local(2026, 10, 1, 12)),
            block(review, local(2026, 10, 31, 22), local(2026, 11, 1, 1)),
        ]
        let october = summary(Period(.month, containing: local(2026, 10, 15), calendar: calendar), blocks)
        let weeks = october.weeks(calendar: calendar)
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0].prefix(3).allSatisfy { $0 == nil })
        #expect(weeks[0][3]?.interval.start == local(2026, 10, 1))
        #expect(weeks[4][5]?.interval.start == local(2026, 10, 31))
        #expect(weeks[4][6] == nil)
        #expect(weeks.joined().compactMap { $0 } == october.days)
        #expect(october.work == 5 * 3600)
        #expect(october.daysWithWork == 2)
        #expect(october.share(of: october.days[0]) == 1)
        #expect(october.share(of: october.days[30]) == 2.0 / 3)
        #expect(october.share(of: october.days[1]) == 0)
        #expect(october.customers.map(\.duration) == [3 * 3600, 2 * 3600])

        var sundayFirst = Fixture.berlin
        sundayFirst.firstWeekday = 1
        let usWeeks = october.weeks(calendar: sundayFirst)
        #expect(usWeeks.count == 5)
        #expect(usWeeks[0].prefix(4).allSatisfy { $0 == nil })
        #expect(usWeeks[0][4]?.interval.start == local(2026, 10, 1))
        #expect(usWeeks[4][6]?.interval.start == local(2026, 10, 31))

        let november = summary(october.period.next(calendar: calendar), blocks)
        let novemberWeeks = november.weeks(calendar: calendar)
        #expect(novemberWeeks.count == 6)
        #expect(novemberWeeks[0].prefix(6).allSatisfy { $0 == nil })
        #expect(novemberWeeks[0][6]?.work == 3600)
        #expect(novemberWeeks[5][0]?.interval.start == local(2026, 11, 30))
        #expect(novemberWeeks[5].dropFirst().allSatisfy { $0 == nil })
    }

    @Test func weekdaySymbolsStartOnTheFirstWeekday() {
        var calendar = Fixture.berlin
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        #expect(calendar.orderedShortWeekdaySymbols == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        calendar.firstWeekday = 1
        #expect(calendar.orderedShortWeekdaySymbols == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    @Test func switchingKindStaysAroundNowOrTheStart() {
        let now = local(2026, 11, 11, 15)
        let thisWeek = Period(.week, containing: now, calendar: calendar)
        #expect(thisWeek.switched(to: .day, now: now, calendar: calendar) == day(2026, 11, 11))
        #expect(
            thisWeek.switched(to: .month, now: now, calendar: calendar)
                == Period(.month, containing: now, calendar: calendar))
        let october = Period(.month, containing: local(2026, 10, 15), calendar: calendar)
        #expect(october.switched(to: .week, now: now, calendar: calendar).interval.start == local(2026, 9, 28))
        #expect(october.switched(to: .day, now: now, calendar: calendar) == day(2026, 10, 1))
    }
}
