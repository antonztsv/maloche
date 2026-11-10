import Foundation
import Testing

@testable import WamaduCore

@MainActor @Suite struct AppModelSettingsTests {
    private let clock = TestClock("09:00")
    private let presenter = FakePresenter()
    private let store = TestDefaults()

    private func makeModel(adjust: @escaping (inout TrackerSettings) -> Void = { _ in }) throws -> AppModel {
        let model = try AppModel(
            database: .inMemory(), stateURL: nil, settingsStore: store.defaults, adjustTracker: adjust, clock: clock,
            calendar: Fixture.berlin)
        model.presenter = presenter
        return model
    }

    private func tick(_ model: AppModel, at time: String, idle: TimeInterval = 0) {
        clock.now = Fixture.at(time)
        model.send(.tick(idleSeconds: idle))
    }

    /// Writing answered by hand at `time`, the span starts there.
    private func startWriting(_ model: AppModel, at time: String) throws -> Int64 {
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: time)
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        return writing
    }

    private func change(_ model: AppModel, _ edit: (inout AppSettings) -> Void) {
        var settings = model.settings
        edit(&settings)
        model.update(settings)
    }

    /// Booked blocks of the day as "Writing 09:00-09:30", with the total of all of them.
    private func booked(_ model: AppModel) throws -> (blocks: [String], total: TimeInterval) {
        let names = Dictionary(uniqueKeysWithValues: try model.database.activities().map { ($0.id!, $0.name) })
        let blocks = try model.database.blocks(in: Fixture.span("00:00", "23:59"))
        return (
            blocks.map { "\(names[$0.activityId]!) \(Fixture.clock($0.startedAt))-\(Fixture.clock($0.endedAt))" },
            blocks.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) }
        )
    }

    @Test func loadsTheStoredSettingsAndStoresChanges() throws {
        var stored = AppSettings()
        stored.checkInInterval = 30 * 60
        stored.rounding = RoundingSettings(stepMinutes: 15, mode: .up, level: .entry)
        stored.save(to: store.defaults)

        let model = try makeModel()
        #expect(model.settings == stored)
        #expect(model.tracker.settings.checkInInterval == 30 * 60)

        change(model) { $0.awayThreshold = 5 * 60 }
        #expect(model.tracker.settings.awayThreshold == 5 * 60)
        #expect(AppSettings.load(from: store.defaults) == model.settings)
        #expect(AppSettings.load(from: store.defaults).awayThreshold == 5 * 60)
    }

    @Test func aLongerIntervalMidSpanAsksLaterAndBooksTheSpanOnce() throws {
        let model = try makeModel()
        let writing = try startWriting(model, at: "09:00")
        tick(model, at: "09:10")

        change(model) { $0.checkInInterval = 30 * 60 }
        tick(model, at: "09:15")
        tick(model, at: "09:29")
        #expect(model.panel == nil)
        tick(model, at: "09:30")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:30"), prefill: writing)))

        model.log(.existing(writing))
        let result = try booked(model)
        #expect(result.blocks == ["Writing 09:00-09:30"])
        #expect(result.total == 30 * 60)
    }

    @Test func aShorterIntervalMidSpanAsksAtTheNextTickForTheWholeSpan() throws {
        let model = try makeModel()
        let writing = try startWriting(model, at: "09:00")
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:08")

        change(model) { $0.checkInInterval = 5 * 60 }
        #expect(model.panel == nil)
        tick(model, at: "09:09")
        #expect(
            model.panel
                == .checkIn(
                    CheckIn(mode: .timed, span: Fixture.span("09:00", "09:09"), prefill: writing, canSplit: true)))

        model.log(.existing(reading))
        let result = try booked(model)
        #expect(result.blocks == ["Writing 09:00-09:04:30", "Reading 09:04:30-09:09"])
        #expect(result.total == 9 * 60)
    }

    @Test func aShorterAwayThresholdCountsFromTheLastInput() throws {
        let model = try makeModel()
        _ = try startWriting(model, at: "09:00")
        tick(model, at: "09:10", idle: 6 * 60)
        #expect(model.panel == nil)

        change(model) { $0.awayThreshold = 5 * 60 }
        tick(model, at: "09:10:05", idle: 6 * 60 + 5)
        #expect(try booked(model).blocks == ["Writing 09:00-09:04"])

        tick(model, at: "09:20")
        #expect(model.panel == .awayReturn(span: Fixture.span("09:04", "09:20"), prefill: model.builtIns.breakId))
    }

    @Test func aNewScheduleIsPublishedAndAppliesRightAway() throws {
        let model = try makeModel()
        tick(model, at: "18:30")
        #expect(model.mode == .off)

        var schedule = WorkSchedule.standard
        schedule.plans[2] = .init(start: 8 * 60, end: 20 * 60)
        change(model) { $0.schedule = schedule }
        #expect(model.schedule == schedule)
        #expect(model.tracker.settings.schedule == schedule)

        tick(model, at: "18:31")
        #expect(model.mode == .tracking)
    }

    @Test func debugAdjustmentsStayAndAreNeverStored() throws {
        let model = try makeModel { $0.checkInInterval = 60 }
        #expect(model.tracker.settings.checkInInterval == 60)
        #expect(model.settings.checkInInterval == 15 * 60)

        change(model) { $0.awayThreshold = 10 * 60 }
        #expect(model.tracker.settings.checkInInterval == 60)
        #expect(model.tracker.settings.awayThreshold == 10 * 60)
        #expect(AppSettings.load(from: store.defaults).checkInInterval == 15 * 60)
    }

    @Test func settingsFromTheMoreMenuClosesThePanelFirst() throws {
        let model = try makeModel()
        _ = try startWriting(model, at: "09:00")
        tick(model, at: "09:15")
        #expect(model.tracker.state.checkInShown)

        model.openSettings()
        #expect(model.panel == nil)
        #expect(presenter.calls.suffix(2) == ["hide", "showSettings"])
        #expect(!model.tracker.state.checkInShown)
    }
}
