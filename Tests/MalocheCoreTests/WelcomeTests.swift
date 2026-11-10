import Foundation
import Testing

@testable import MalocheCore

@MainActor @Suite struct WelcomeTests {
    private let store = MemorySettingsStore()

    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Fixture.berlin
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func makeModel(
        database: AppDatabase? = nil, calendar: Calendar = calendar(firstWeekday: 2)
    ) throws -> AppModel {
        try AppModel(
            database: database ?? .inMemory(), stateURL: nil, settingsStore: store, clock: TestClock("09:00"),
            calendar: calendar)
    }

    @Test func isDueWithNothingStoredAndNoTimeBooked() throws {
        let model = try makeModel()
        #expect(!model.settings.welcomeDone)
        #expect(model.welcomeDue)
    }

    @Test func timeBookedCountsAsDoneWithNothingStored() throws {
        let database = try AppDatabase.inMemory()
        let writing = try database.createActivity(name: "Writing").id!
        try database.insert(
            block: Block(
                activityId: writing, startedAt: Fixture.at("08:00"), endedAt: Fixture.at("08:30"), source: .checkIn))
        #expect(try !makeModel(database: database).welcomeDue)
    }

    @Test func settingsStoredBeforeTheWelcomeExistedCountAsDone() throws {
        store.data = Data(#"{"checkInInterval": 1800}"#.utf8)
        let model = try makeModel()
        #expect(model.settings.welcomeDone)
        #expect(model.settings.checkInInterval == 1800)
    }

    @Test func startStoresTheChoicesAndIsNotDueAgain() throws {
        let model = try makeModel()
        var welcome = Welcome(settings: model.settings, calendar: model.calendar)
        welcome.days = [1, 3, 7]
        welcome.plan = .init(start: 9 * 60 + 30, end: 17 * 60)
        welcome.checkInInterval = 30 * 60
        model.finishWelcome(welcome)

        let plan = WorkSchedule.Plan(start: 9 * 60 + 30, end: 17 * 60)
        #expect(model.settings.schedule == WorkSchedule(plans: [1: plan, 3: plan, 7: plan]))
        #expect(model.settings.checkInInterval == 30 * 60)
        #expect(model.settings.welcomeDone)
        #expect(model.tracker.settings.schedule == model.settings.schedule)
        let reloaded = try makeModel()
        #expect(reloaded.settings == model.settings)
        #expect(!reloaded.welcomeDue)
    }

    @Test func startWithTheDefaultsStillMarksItDone() throws {
        let model = try makeModel()
        model.finishWelcome(Welcome(settings: model.settings, calendar: model.calendar))
        var expected = AppSettings()
        expected.welcomeDone = true
        #expect(try makeModel().settings == expected)
    }

    @Test func closingKeepsTheSettingsAndIsNotDueAgain() throws {
        let model = try makeModel()
        model.finishWelcome(nil)
        var expected = AppSettings()
        expected.welcomeDone = true
        #expect(model.settings == expected)
        #expect(try makeModel().settings == expected)
    }

    @Test func startsFromTheDefaults() {
        let welcome = Welcome(settings: AppSettings(), calendar: Self.calendar(firstWeekday: 2))
        #expect(welcome.days == [2, 3, 4, 5, 6])
        #expect(welcome.plan == .init(start: 8 * 60, end: 18 * 60))
        #expect(welcome.checkInInterval == 15 * 60)
    }

    @Test func differentTimesPerDayShowTheFirstPlannedDayInTheWeek() throws {
        var settings = AppSettings()
        settings.schedule = WorkSchedule(plans: [
            1: .init(start: 10 * 60, end: 14 * 60), 2: .init(start: 9 * 60, end: 17 * 60),
            3: .init(start: 7 * 60, end: 15 * 60),
        ])
        let mondayFirst = Welcome(settings: settings, calendar: Self.calendar(firstWeekday: 2))
        #expect(mondayFirst.days == [1, 2, 3])
        #expect(mondayFirst.plan == .init(start: 9 * 60, end: 17 * 60))
        #expect(Welcome(settings: settings, calendar: Self.calendar(firstWeekday: 1)).plan.start == 10 * 60)

        let model = try makeModel()
        model.update(settings)
        model.finishWelcome(mondayFirst)
        let plan = WorkSchedule.Plan(start: 9 * 60, end: 17 * 60)
        #expect(model.settings.schedule == WorkSchedule(plans: [1: plan, 2: plan, 3: plan]))
    }

    @Test func noPlannedDayShowsEightToSix() {
        var settings = AppSettings()
        settings.schedule = WorkSchedule(plans: [:])
        let welcome = Welcome(settings: settings, calendar: Self.calendar(firstWeekday: 2))
        #expect(welcome.days.isEmpty)
        #expect(welcome.plan == .init(start: 8 * 60, end: 18 * 60))
    }

    @Test func weekdaysStartOnTheFirstWeekday() {
        #expect(Self.calendar(firstWeekday: 1).orderedWeekdays == [1, 2, 3, 4, 5, 6, 7])
        #expect(Self.calendar(firstWeekday: 2).orderedWeekdays == [2, 3, 4, 5, 6, 7, 1])
    }
}
