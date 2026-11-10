import Foundation
import Testing

@testable import WamaduCore

/// A uniquely named defaults suite, removed again when the test ends.
final class TestDefaults: @unchecked Sendable {
    private let name = "wamadu-tests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: name)! }

    deinit { defaults.removePersistentDomain(forName: name) }
}

@Suite struct AppSettingsTests {
    private let store = TestDefaults()

    @Test func defaults() {
        let settings = AppSettings()
        #expect(settings.checkInInterval == 15 * 60)
        #expect(settings.awayThreshold == 15 * 60)
        #expect(settings.schedule == .standard)
        #expect(settings.rounding.stepMinutes == nil)
        #expect(settings.shortcuts.count == 3)
        #expect(ShortcutAction.allCases.allSatisfy { settings.shortcuts[$0] == $0.defaultShortcut })
        #expect(settings.tracker == TrackerSettings())
    }

    @Test func roundTripThroughTheStore() {
        var settings = AppSettings()
        settings.checkInInterval = 30 * 60
        settings.awayThreshold = 5 * 60
        settings.schedule.plans[2] = nil
        settings.schedule.plans[7] = .init(start: 9 * 60 + 30, end: 13 * 60)
        settings.rounding = RoundingSettings(stepMinutes: 6, mode: .up, level: .period)
        settings.shortcuts[.toggleBreak] = nil
        settings.shortcuts[.openDashboard] = Shortcut(keyCode: 0x7A, modifiers: [.control, .shift])
        settings.save(to: store.defaults)
        #expect(AppSettings.load(from: store.defaults) == settings)
        #expect(AppSettings.load(from: store.defaults).shortcuts[.toggleBreak] == nil)
    }

    @Test func nothingStoredGivesTheDefaults() {
        #expect(AppSettings.load(from: store.defaults) == AppSettings())
    }

    @Test func anUnreadableValueGivesTheDefaults() {
        store.defaults.set(Data("not json".utf8), forKey: AppSettings.defaultsKey)
        #expect(AppSettings.load(from: store.defaults) == AppSettings())
        store.defaults.set("a string", forKey: AppSettings.defaultsKey)
        #expect(AppSettings.load(from: store.defaults) == AppSettings())
    }

    @Test func readableFieldsStayWhenOthersAreMissingOrDamaged() {
        let json = #"{"checkInInterval": 1800, "rounding": 42, "laterSetting": true}"#
        store.defaults.set(Data(json.utf8), forKey: AppSettings.defaultsKey)
        var expected = AppSettings()
        expected.checkInInterval = 1800
        #expect(AppSettings.load(from: store.defaults) == expected)
    }
}
