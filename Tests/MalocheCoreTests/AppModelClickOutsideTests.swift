import Foundation
import Testing

@testable import MalocheCore

/// K6: a click outside closes what the user opened, prompts the app showed by itself stay.
@MainActor @Suite struct AppModelClickOutsideTests {
    private let clock = TestClock("09:00")
    private let presenter = FakePresenter()

    private func makeModel() throws -> AppModel {
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: clock, calendar: Fixture.berlin)
        model.presenter = presenter
        _ = try model.database.createActivity(name: "Writing")
        model.send(.tick(idleSeconds: 0))
        return model
    }

    private func blockCount(_ model: AppModel) throws -> Int {
        try model.database.blocks(in: DateInterval(start: Fixture.at("00:00"), end: Fixture.at("23:59"))).count
    }

    @Test func dashboardClosesOnClickOutside() throws {
        let model = try makeModel()
        model.statusItemClicked()
        #expect(presenter.isVisible)

        model.panelLostFocus()

        #expect(!presenter.isVisible)
        #expect(model.panel == nil)
    }

    @Test func checkInOpenedByHandClosesWithoutBooking() throws {
        let model = try makeModel()
        model.shortcut(.openCheckIn)
        let state = model.tracker.state
        let blocks = try blockCount(model)

        model.panelLostFocus()

        #expect(!presenter.isVisible)
        #expect(model.tracker.state == state)
        #expect(try blockCount(model) == blocks)
    }

    @Test func checkInFromTheNowRowClosesThePanel() throws {
        let model = try makeModel()
        model.statusItemClicked()
        model.checkIn()

        model.panelLostFocus()

        #expect(!presenter.isVisible)
        #expect(model.panel == nil)
    }

    @Test func timedCheckInStaysWhenTheUserClicksElsewhere() throws {
        let model = try makeModel()
        clock.now = Fixture.at("09:15")
        model.send(.tick(idleSeconds: 0))
        #expect(model.panel?.isPrompt == true)
        presenter.focus()

        model.panelLostFocus()

        #expect(presenter.isVisible)
        #expect(model.panel?.isPrompt == true)
    }

    @Test func aSessionRightAfterAClickOutsideOpensTheDashboardAgain() throws {
        let model = try makeModel()
        model.statusItemClicked()
        model.panelLostFocus()

        model.statusItemClicked()

        #expect(presenter.isVisible)
        #expect(model.panel?.isPrompt == false)
    }
}
