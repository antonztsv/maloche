import AppKit
import MalocheCore
import SwiftUI
import Testing

@testable import Maloche

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
        #expect(controller.window.title == "Welcome to maloche")
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

    /// Return in the welcome view, hosted in a window that is never shown or key; true when Start ran.
    private func pressReturn(_ model: AppModel) -> Bool {
        _ = NSApplication.shared
        var started = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeWindowController.width, height: 600), styleMask: .borderless,
            backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: WelcomeView(model: model, openAtLogin: false) { _, _ in started = true })
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        _ = window.performKeyEquivalent(with: event)
        return started
    }

    /// Counts the closes Escape asks for, instead of closing.
    private final class Closing: NSWindow {
        var closes = 0
        override func close() { closes += 1 }
    }

    /// Without a focused field Escape reaches no cancelOperation, a key equivalent always closes.
    @Test func escapeClosesTheWelcome() throws {
        let (_, model) = try makeController()
        let window = Closing(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeWindowController.width, height: 600), styleMask: .borderless,
            backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: WelcomeView(model: model, openAtLogin: false) { _, _ in })
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!

        #expect(window.performKeyEquivalent(with: escape))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(window.closes == 1)
    }

    @Test func startNeedsAWorkDay() throws {
        let (_, model) = try makeController()
        #expect(pressReturn(model))

        var settings = model.settings
        settings.schedule = WorkSchedule(plans: [:])
        model.update(settings)
        #expect(!pressReturn(model))
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
