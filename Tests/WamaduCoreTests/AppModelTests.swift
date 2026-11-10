import Foundation
import GRDB
import Testing

@testable import WamaduCore

@MainActor
final class FakePresenter: PanelPresenter {
    var isVisible = false
    var isKey = false
    var calls: [String] = []

    func show(focus: Bool) {
        isVisible = true
        isKey = focus
        calls.append("show(focus: \(focus))")
    }

    func update() { calls.append("update") }

    func focus() {
        isKey = true
        calls.append("focus")
    }

    func hide() {
        isVisible = false
        isKey = false
        calls.append("hide")
    }
}

final class TestClock: WallClock, @unchecked Sendable {
    var now: Date

    init(_ time: String) { now = Fixture.at(time) }
}

@MainActor @Suite struct AppModelTests {
    private let clock = TestClock("09:00")
    private let presenter = FakePresenter()

    private func makeModel(_ database: AppDatabase? = nil, stateURL: URL? = nil) throws -> AppModel {
        let model = try AppModel(
            database: database ?? .inMemory(), stateURL: stateURL, clock: clock, calendar: Fixture.berlin)
        model.presenter = presenter
        return model
    }

    /// Present at `time`: the user worked right up to it.
    private func tick(_ model: AppModel, at time: String) {
        clock.now = Fixture.at(time)
        model.send(.tick(idleSeconds: 0))
    }

    /// Blocks of the day with adjacent blocks of one activity merged, as "Writing 09:00-09:10".
    private func timeline(_ model: AppModel) throws -> [String] {
        let names = Dictionary(uniqueKeysWithValues: try model.database.activities().map { ($0.id!, $0.name) })
        var merged: [Block] = []
        for block in try model.database.blocks(in: DateInterval(start: Fixture.at("00:00"), end: Fixture.at("23:59"))) {
            if let last = merged.last, last.activityId == block.activityId, last.endedAt == block.startedAt {
                merged[merged.count - 1].endedAt = block.endedAt
            } else {
                merged.append(block)
            }
        }
        return merged.map { "\(names[$0.activityId]!) \(Fixture.clock($0.startedAt))-\(Fixture.clock($0.endedAt))" }
    }

    @Test func iconClickOpensTheCheckInByHandAndTheAnswerStartsNow() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:00")

        clock.now = Fixture.at("09:10")
        model.statusItemClicked()
        #expect(presenter.calls == ["show(focus: true)"])
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:00", "09:10"), prefill: nil)))
        model.log(.existing(writing))
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")

        clock.now = Fixture.at("09:12")
        model.statusItemClicked()
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:10", "09:12"), prefill: writing)))
        model.log(.existing(reading))
        tick(model, at: "09:14")
        #expect(try timeline(model) == ["Writing 09:00-09:12", "Reading 09:12-09:14"])
        #expect(model.catalog.usedToday == [reading, writing])
    }

    @Test func aTimedPromptShowsWithoutFocusAndItsAnswerCoversTheSpan() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        let reading = try model.database.createActivity(name: "Reading").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.existing(writing))

        tick(model, at: "09:15")
        #expect(presenter.calls.last == "show(focus: false)")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
        model.log(.existing(reading))
        #expect(model.panel == nil)
        #expect(try timeline(model) == ["Writing 09:00-09:07:30", "Reading 09:07:30-09:15"])
    }

    @Test func aDueCheckInTurnsAnOpenManualCheckInIntoTheTimedOne() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.existing(writing))

        clock.now = Fixture.at("09:14")
        model.statusItemClicked()
        tick(model, at: "09:15")
        #expect(presenter.calls.suffix(2) == ["show(focus: true)", "update"])
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
    }

    @Test func escapeDismissesATimedPromptAndOnlyClosesAManualOne() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.existing(writing))

        clock.now = Fixture.at("09:05")
        model.statusItemClicked()
        let before = model.tracker.state
        model.close()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(model.tracker.state == before)

        tick(model, at: "09:15")
        #expect(model.tracker.state.checkInShown)
        model.close()
        #expect(model.panel == nil)
        #expect(!model.tracker.state.checkInShown)
    }

    @Test func iconClickFocusesAnUnfocusedPromptAndClosesAFocusedOne() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.existing(writing))
        tick(model, at: "09:15")

        model.statusItemClicked()
        #expect(presenter.calls.last == "focus")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("09:00", "09:15"), prefill: writing)))
        model.statusItemClicked()
        #expect(presenter.calls.last == "hide")
        #expect(!model.tracker.state.checkInShown)
    }

    @Test func breakClosesThePanelAndStartsABreak() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.existing(writing))

        clock.now = Fixture.at("09:10")
        model.statusItemClicked()
        model.startBreak()
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        #expect(model.tracker.mode == .onBreak)
    }

    @Test func iconClickDuringABreakAsksAboutTheBreak() throws {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.existing(writing))
        clock.now = Fixture.at("09:05")
        model.send(.startBreak)

        clock.now = Fixture.at("09:20")
        model.statusItemClicked()
        #expect(model.tracker.state.phase == .breakReturn(returnAt: Fixture.at("09:20")))
        #expect(model.panel == .checkIn(CheckIn(mode: .manual, span: Fixture.span("09:05", "09:20"), prefill: writing)))
    }

    @Test func aNewNameCreatesTheActivity() throws {
        let model = try makeModel()
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.create(name: "Kickoff", projectId: nil))

        let kickoff = try #require(try model.database.activities().first { $0.name == "Kickoff" })
        #expect(kickoff.projectId == nil)
        #expect(model.tracker.currentActivity == kickoff.id)
        #expect(model.catalog.activity(kickoff.id) == kickoff)
    }

    @Test func trackerStateSurvivesARelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appending(path: "tracker-state.json")
        let database = try AppDatabase.inMemory()
        let model = try makeModel(database, stateURL: stateURL)
        let writing = try database.createActivity(name: "Writing").id!
        tick(model, at: "09:00")
        model.statusItemClicked()
        model.log(.existing(writing))

        let relaunched = try makeModel(database, stateURL: stateURL)
        #expect(relaunched.tracker.state == model.tracker.state)
        #expect(relaunched.tracker.currentActivity == writing)
    }

    @Test func anUnreadableStateStartsFresh() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appending(path: "tracker-state.json")
        try Data("not json".utf8).write(to: stateURL)
        #expect(try makeModel(stateURL: stateURL).tracker.state == TrackerState())
    }
}
