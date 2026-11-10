import AppKit
import Testing
import WamaduCore

@testable import Wamadu

/// The welcome window is built but never shown, the login item is a fake.
@MainActor @Suite struct WelcomeWindowTests {
    private struct Failed: Error {}

    private final class LoginItemFake {
        var enabled = false
        var fails = false
        var calls: [Bool] = []

        func set(_ enabled: Bool) throws {
            calls.append(enabled)
            if fails { throw Failed() }
            self.enabled = enabled
        }
    }

    private let loginItem = LoginItemFake()

    private func makeController() throws -> (WelcomeWindowController, AppModel) {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let controller = WelcomeWindowController(
            model: model, isLoginItem: { [loginItem] in loginItem.enabled },
            setLoginItem: { [loginItem] in try loginItem.set($0) })
        return (controller, model)
    }

    @Test func startStoresTheChoicesSetsTheLoginItemAndCloses() throws {
        let (controller, model) = try makeController()
        #expect(controller.window.title == "Welcome to wamadu")
        var welcome = Welcome(settings: model.settings, calendar: model.calendar)
        welcome.days = [2, 4]
        welcome.checkInInterval = 20 * 60
        controller.start(welcome, openAtLogin: true)

        #expect(loginItem.calls == [true])
        #expect(model.settings.welcomeDone)
        #expect(model.settings.checkInInterval == 20 * 60)
        #expect(model.settings.schedule.plans.keys.sorted() == [2, 4])
        #expect(!controller.window.isVisible)
        #expect(NSApplication.shared.keyWindow == nil)
    }

    @Test func anUnchangedLoginItemIsLeftAlone() throws {
        let (controller, model) = try makeController()
        controller.start(Welcome(settings: model.settings, calendar: model.calendar), openAtLogin: false)
        #expect(loginItem.calls.isEmpty)
        #expect(model.settings.welcomeDone)
    }

    @Test func aFailingLoginItemStillStarts() throws {
        let (controller, model) = try makeController()
        loginItem.fails = true
        controller.start(Welcome(settings: model.settings, calendar: model.calendar), openAtLogin: true)
        #expect(loginItem.calls == [true])
        #expect(model.settings.welcomeDone)
    }

    @Test func closingKeepsTheSettingsAndMarksItDone() throws {
        let (controller, model) = try makeController()
        controller.window.close()
        var expected = AppSettings()
        expected.welcomeDone = true
        #expect(model.settings == expected)
        #expect(loginItem.calls.isEmpty)
    }
}
