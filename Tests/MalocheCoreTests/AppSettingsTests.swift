import Foundation
import Testing

@testable import MalocheCore

/// Settings kept in memory, nothing reaches the user defaults.
final class MemorySettingsStore: SettingsStore {
    var data: Data?

    func storedSettings() -> Data? { data }

    func storeSettings(_ data: Data) { self.data = data }
}

@Suite struct AppSettingsTests {
    private let store = MemorySettingsStore()

    @Test func defaults() {
        let settings = AppSettings()
        #expect(settings.checkInInterval == 15 * 60)
        #expect(settings.awayThreshold == 15 * 60)
        #expect(settings.schedule == .standard)
        #expect(settings.rounding.stepMinutes == nil)
        #expect(settings.shortcuts.count == 3)
        #expect(ShortcutAction.allCases.allSatisfy { settings.shortcuts[$0] == $0.defaultShortcut })
        #expect(settings.tracker == TrackerSettings())
        #expect(settings.backup.automatic)
        #expect(settings.backup.keep == 30)
        #expect(settings.backup.folder == nil)
        #expect(!settings.showInDock)
        #expect(!settings.checkForUpdates)
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
        settings.backup = BackupSettings(automatic: false, folder: "/Volumes/Archive/maloche", keep: 7)
        settings.showInDock = true
        settings.checkForUpdates = true
        settings.save(to: store)
        #expect(AppSettings.load(from: store) == settings)
        #expect(AppSettings.load(from: store).showInDock)
        #expect(AppSettings.load(from: store).checkForUpdates)
        #expect(AppSettings.load(from: store).shortcuts[.toggleBreak] == nil)
    }

    @Test func nothingStoredGivesTheDefaults() {
        #expect(AppSettings.load(from: store) == AppSettings())
    }

    @Test func anUnreadableValueGivesTheDefaults() {
        store.data = Data("not json".utf8)
        #expect(AppSettings.load(from: store) == AppSettings())
    }

    @Test func readableFieldsStayWhenOthersAreMissingOrDamaged() {
        let json = #"{"checkInInterval": 1800, "rounding": 42, "laterSetting": true}"#
        store.data = Data(json.utf8)
        var expected = AppSettings()
        expected.checkInInterval = 1800
        expected.welcomeDone = true
        #expect(!expected.showInDock)
        #expect(!expected.checkForUpdates)
        #expect(AppSettings.load(from: store) == expected)
    }
}
