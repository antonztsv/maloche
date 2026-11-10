import Foundation
import Testing

@testable import WamaduCore

/// S10: the popover of an activity on the shown day edits, moves and deletes its spans.
@MainActor @Suite struct AppModelEntryTests {
    private let clock = TestClock("17:30")
    private let presenter = FakePresenter()
    private let today = Period(.day, containing: Fixture.at("12:00"), calendar: Fixture.berlin)

    private struct Setup {
        var model: AppModel
        var writing: Int64
        var reading: Int64
    }

    /// Writing 10:00 to 12:15 in two blocks and 16:00 to 17:00, Reading between, today's dashboard shown.
    private func makeModel() throws -> Setup {
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: clock, calendar: Fixture.berlin)
        model.presenter = presenter
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        for (id, from, to) in [
            (writing, "10:00", "11:00"), (writing, "11:00", "12:15"), (reading, "12:15", "16:00"),
            (writing, "16:00", "17:00"),
        ] {
            try book(model, id, from, to)
        }
        model.showDashboard(today)
        return Setup(model: model, writing: writing, reading: reading)
    }

    private func book(_ model: AppModel, _ id: Int64, _ from: String, _ to: String) throws {
        try model.database.insert(
            block: Block(activityId: id, startedAt: Fixture.at(from), endedAt: Fixture.at(to), source: .checkIn))
    }

    /// Stored blocks of today as "Writing 10:00-11:00".
    private func blocks(_ model: AppModel) throws -> [String] {
        let names = Dictionary(uniqueKeysWithValues: try model.database.activities().map { ($0.id!, $0.name) })
        return try model.database.blocks(in: today.interval).map {
            "\(names[$0.activityId]!) \(Fixture.clock($0.startedAt))-\(Fixture.clock($0.endedAt))"
        }
    }

    private func shownDay(_ model: AppModel) -> DashboardDay? {
        if case .dashboard(let day) = model.panel { day } else { nil }
    }

    @Test func theEntryShowsTheSpansOfTheActivityOnTheShownDay() throws {
        let setup = try makeModel()
        let model = setup.model
        let entry = try #require(model.entry(activityId: setup.writing))
        #expect(entry.day == today.interval)
        #expect(entry.spans.map(\.interval) == [Fixture.span("10:00", "12:15"), Fixture.span("16:00", "17:00")])
        #expect(model.entry(activityId: setup.reading)?.spans.map(\.interval) == [Fixture.span("12:15", "16:00")])
        #expect(model.entry(activityId: model.builtIns.breakId) == nil)
        model.close()
        #expect(model.entry(activityId: setup.writing) == nil)
    }

    @Test func plusFifteenMovesTheEndOverTheNextActivityAndTheDashboardRefreshes() throws {
        let setup = try makeModel()
        let model = setup.model
        let entry = try #require(model.entry(activityId: setup.writing))

        model.extendSpan(entry.spans[0], of: entry, by: 15 * 60)

        #expect(try blocks(model) == ["Writing 10:00-12:30", "Reading 12:30-16:00", "Writing 16:00-17:00"])
        #expect(
            shownDay(model)?.blocks.map(\.endedAt) == [Fixture.at("12:30"), Fixture.at("16:00"), Fixture.at("17:00")])
        #expect(model.entry(activityId: setup.writing)?.spans.first?.interval == Fixture.span("10:00", "12:30"))
        #expect(model.catalog.usedToday == [setup.writing, setup.reading])
        #expect(presenter.failures == 0)
    }

    @Test func plusFifteenStopsAtNow() throws {
        let setup = try makeModel()
        let model = setup.model
        clock.now = Fixture.at("17:10")
        let entry = try #require(model.entry(activityId: setup.writing))

        model.extendSpan(entry.spans[1], of: entry, by: 15 * 60)
        #expect(try blocks(model).last == "Writing 16:00-17:10")
        #expect(presenter.failures == 0)

        let extended = try #require(model.entry(activityId: setup.writing))
        model.extendSpan(extended.spans[1], of: extended, by: 15 * 60)
        #expect(try blocks(model).last == "Writing 16:00-17:10")
        #expect(presenter.failures == 1)
    }

    @Test func minusFifteenKeepsAtLeastOneMinute() throws {
        let setup = try makeModel()
        let model = setup.model
        let entry = try #require(model.entry(activityId: setup.writing))
        model.setSpan(entry.spans[1], of: entry, start: Fixture.at("16:00"), end: Fixture.at("16:16"))

        let short = try #require(model.entry(activityId: setup.writing))
        model.extendSpan(short.spans[1], of: short, by: -15 * 60)
        #expect(try blocks(model).last == "Writing 16:00-16:01")
        #expect(presenter.failures == 0)

        let shortest = try #require(model.entry(activityId: setup.writing))
        model.extendSpan(shortest.spans[1], of: shortest, by: -15 * 60)
        #expect(try blocks(model).last == "Writing 16:00-16:01")
        #expect(presenter.failures == 1)
    }

    @Test func aSpanEndsAfterItsStartAndNotAfterNow() throws {
        let setup = try makeModel()
        let model = setup.model
        let entry = try #require(model.entry(activityId: setup.writing))
        let before = try blocks(model)

        model.setSpan(entry.spans[1], of: entry, start: Fixture.at("16:00"), end: Fixture.at("16:00"))
        model.setSpan(entry.spans[1], of: entry, start: Fixture.at("17:00"), end: Fixture.at("16:00"))
        model.setSpan(entry.spans[1], of: entry, start: Fixture.at("16:00"), end: Fixture.at("17:31"))

        #expect(presenter.failures == 3)
        #expect(try blocks(model) == before)
    }

    @Test func aSpanStaysOnItsDay() throws {
        let setup = try makeModel()
        let model = setup.model
        try book(model, setup.reading, "2026-11-08 23:00", "01:00")
        model.showDashboard(today)
        let entry = try #require(model.entry(activityId: setup.reading))
        let night = entry.spans[0]
        #expect(night.interval == Fixture.span("2026-11-08 23:00", "01:00"))

        model.setSpan(entry.spans[1], of: entry, start: Fixture.at("2026-11-08 23:30"), end: Fixture.at("16:00"))
        model.setSpan(night, of: entry, start: Fixture.at("2026-11-08 22:00"), end: Fixture.at("01:00"))
        model.setSpan(night, of: entry, start: night.interval.start, end: Fixture.at("2026-11-08 23:30"))
        #expect(presenter.failures == 3)

        model.setSpan(night, of: entry, start: night.interval.start, end: Fixture.at("02:00"))
        #expect(presenter.failures == 3)
        #expect(try blocks(model).first == "Reading 11-08 23:00-02:00")

        model.showDashboard(today.previous(calendar: Fixture.berlin))
        let yesterday = try #require(model.entry(activityId: setup.reading))
        model.setSpan(
            yesterday.spans[0], of: yesterday, start: Fixture.at("2026-11-08 23:00"), end: Fixture.at("03:00"))
        #expect(presenter.failures == 4)
        model.setSpan(
            yesterday.spans[0], of: yesterday, start: Fixture.at("2026-11-08 23:15"), end: Fixture.at("02:00"))
        #expect(presenter.failures == 4)
        #expect(try blocks(model).first == "Reading 11-08 23:15-02:00")
    }

    @Test func movingTheEntryBooksAllItsSpansToTheOtherActivity() throws {
        let setup = try makeModel()
        let model = setup.model
        let breakId = model.builtIns.breakId
        let entry = try #require(model.entry(activityId: setup.writing))

        model.moveEntry(entry, to: setup.writing)
        #expect(try blocks(model).first == "Writing 10:00-11:00")
        model.moveEntry(entry, to: breakId)

        #expect(
            try blocks(model) == [
                "Break 10:00-11:00", "Break 11:00-12:15", "Reading 12:15-16:00", "Break 16:00-17:00",
            ])
        #expect(model.entry(activityId: setup.writing) == nil)
        #expect(model.entry(activityId: breakId)?.spans.count == 2)
        #expect(model.catalog.usedToday == [breakId, setup.reading])
        model.moveEntry(try #require(model.entry(activityId: breakId)), to: 999)
        #expect(presenter.failures == 1)
        #expect(try blocks(model).first == "Break 10:00-11:00")
    }

    @Test func deletingTheEntryRemovesAllItsSpans() throws {
        let setup = try makeModel()
        let model = setup.model
        let entry = try #require(model.entry(activityId: setup.writing))

        model.deleteEntry(entry)

        #expect(try blocks(model) == ["Reading 12:15-16:00"])
        #expect(shownDay(model)?.blocks.map(\.activityId) == [setup.reading])
        #expect(model.entry(activityId: setup.writing) == nil)
        #expect(presenter.failures == 0)
    }

    @Test func afterDoneForTodayTheDashboardShowsTheEditedDay() throws {
        clock.now = Fixture.at("09:00")
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: clock, calendar: Fixture.berlin)
        model.presenter = presenter
        let writing = try model.database.createActivity(name: "Writing").id!
        model.send(.tick(idleSeconds: 0))
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        clock.now = Fixture.at("09:10")
        model.send(.tick(idleSeconds: 0))
        model.doneForToday()
        model.statusItemClicked()
        let entry = try #require(model.entry(activityId: writing))

        model.setSpan(entry.spans[0], of: entry, start: Fixture.at("09:00"), end: Fixture.at("09:05"))

        #expect(shownDay(model)?.blocks.map(\.endedAt) == [Fixture.at("09:05")])
    }

    /// The tracker books the running span again and again, it is not part of an entry and edits end before it.
    @Test func theRunningSpanStaysWithTheTrackerAndEditsStopAtItsStart() throws {
        clock.now = Fixture.at("09:00")
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: clock, calendar: Fixture.berlin)
        model.presenter = presenter
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        model.send(.tick(idleSeconds: 0))
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        clock.now = Fixture.at("09:10")
        model.send(.tick(idleSeconds: 0))
        model.shortcut(.openCheckIn)
        model.log(.existing(reading))
        clock.now = Fixture.at("09:20")
        model.send(.tick(idleSeconds: 0))
        model.showDashboard(today)
        #expect(try blocks(model) == ["Writing 09:00-09:10", "Reading 09:10-09:20"])

        #expect(model.entry(activityId: reading) == nil)
        let entry = try #require(model.entry(activityId: writing))
        model.extendSpan(entry.spans[0], of: entry, by: 15 * 60)
        model.setSpan(entry.spans[0], of: entry, start: Fixture.at("09:00"), end: Fixture.at("09:15"))
        #expect(presenter.failures == 2)
        model.setSpan(entry.spans[0], of: entry, start: Fixture.at("09:00"), end: Fixture.at("09:05"))
        clock.now = Fixture.at("09:22")
        model.send(.tick(idleSeconds: 0))
        #expect(try blocks(model) == ["Writing 09:00-09:05", "Reading 09:10-09:22"])
    }
}
