import Foundation
import Testing

@testable import MalocheCore

/// S8: the Manage Activities window changes activities while the tracker runs.
@MainActor @Suite struct AppModelManageTests {
    private let clock = TestClock("09:00")
    private let presenter = FakePresenter()

    private func makeModel() throws -> AppModel {
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: clock, calendar: Fixture.berlin)
        model.presenter = presenter
        return model
    }

    private func tick(_ model: AppModel, at time: String) {
        clock.now = Fixture.at(time)
        model.send(.tick(idleSeconds: 0))
    }

    /// Writing answered by hand at 09:00.
    private func writingFrom0900(_ model: AppModel) throws -> Int64 {
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        return writing
    }

    /// Stored blocks of the day as "Writing 09:00-09:30".
    private func booked(_ model: AppModel) throws -> [String] {
        let names = Dictionary(uniqueKeysWithValues: try model.database.activities().map { ($0.id!, $0.name) })
        return try model.database.blocks(in: Fixture.span("00:00", "23:59")).map {
            "\(names[$0.activityId] ?? "?") \(Fixture.clock($0.startedAt))-\(Fixture.clock($0.endedAt))"
        }
    }

    @Test func manageActivitiesFromTheMoreMenuClosesThePanelFirst() throws {
        let model = try makeModel()
        model.statusItemClicked()
        #expect(model.panel != nil)

        model.openManageActivities()

        #expect(model.panel == nil)
        #expect(presenter.calls.suffix(2) == ["hide", "showManageActivities"])
    }

    @Test func aChangeReloadsTheCatalogAndTheShownDay() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:10")
        model.statusItemClicked()

        try model.manage { try $0.renameActivity(id: writing, to: "Drafting") }
        #expect(model.catalog.activity(writing)?.name == "Drafting")

        try model.merge([writing], into: reading)
        #expect(model.catalog.activity(writing) == nil)
        guard case .dashboard(let day) = model.panel else {
            Issue.record("the dashboard stays")
            return
        }
        #expect(day.blocks.map(\.activityId) == [reading])
    }

    /// Created through the window, so the catalog has it.
    private func create(_ model: AppModel, _ name: String) throws -> Int64 {
        var id: Int64?
        try model.manage { id = try $0.createActivity(name: name).id }
        return try #require(id)
    }

    @Test func aFailedChangeLeavesTheCatalog() throws {
        let model = try makeModel()
        let writing = try create(model, "Writing")
        _ = try create(model, "Reading")
        model.statusItemClicked()
        #expect(throws: MalocheError.duplicateName) {
            try model.manage { try $0.renameActivity(id: writing, to: "reading") }
        }
        #expect(model.catalog.activity(writing)?.name == "Writing")
        #expect(presenter.failures == 0)
    }

    /// K22: the names the app shows for Break and Private reach the database through the model.
    @Test func theShownNamesAreReservedInTheWindow() throws {
        let model = try AppModel(
            database: .inMemory(), stateURL: nil, builtInNames: [.break: "Pause", .private: "Privat"], clock: clock,
            calendar: Fixture.berlin)
        #expect(throws: MalocheError.duplicateName) { try model.manage { _ = try $0.createActivity(name: "pause") } }
        #expect(model.catalog.activities.filter { $0.kind != .regular }.map(\.name) == ["Pause", "Privat"])
    }

    @Test func mergingTheRunningActivityKeepsBookingTheTarget() throws {
        let model = try makeModel()
        let writing = try writingFrom0900(model)
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:10")

        try model.merge([writing], into: reading)
        #expect(model.currentActivity == reading)
        tick(model, at: "09:20")

        #expect(try booked(model) == ["Reading 09:00-09:20"])
        #expect(presenter.failures == 0)
    }

    @Test func aMergedActivityStillShownInAPromptIsNotBooked() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)
        let prompt = model.panel

        try model.merge([writing], into: reading)
        model.log(.existing(writing))

        #expect(presenter.failures == 1)
        #expect(model.panel == prompt)
        #expect(model.currentActivity == nil)
        model.log(.existing(reading))
        #expect(model.currentActivity == reading)
    }

    @Test func theNameOfAnArchivedActivityInACheckInBringsItBack() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        try model.manage { try $0.setArchived(true, activities: [writing, reading]) }
        tick(model, at: "09:00")
        model.shortcut(.openCheckIn)

        model.log(.create(name: " writing", projectId: nil))

        #expect(model.currentActivity == writing)
        #expect(model.catalog.activities.filter { $0.kind == .regular }.count == 2)
        #expect(model.catalog.activity(writing)?.archived == false)

        tick(model, at: "09:30")
        model.shortcut(.openCheckIn)
        model.log(.existing(reading))
        #expect(model.catalog.activity(reading)?.archived == false)
    }

    @Test func thisMonthCountsOnlyTheCurrentCalendarMonth() throws {
        let model = try makeModel()
        let writing = try create(model, "Writing")
        for (from, to) in [("2026-10-31 23:00", "2026-11-01 01:00"), ("2026-11-09 08:00", "2026-11-09 08:30")] {
            try model.database.insert(
                block: Block(
                    activityId: writing, startedAt: Fixture.at(from), endedAt: Fixture.at(to), source: .checkIn))
        }
        model.statusItemClicked()

        let row = try model.activityOverview().rows(.all).first
        #expect(row?.id == writing)
        #expect(row?.thisMonth == TimeInterval(90 * 60))
    }
}
