import Foundation
import Testing

@testable import WamaduCore

/// S14: automatic backups at launch and once a day, restore with a backup of the current data first.
@MainActor @Suite struct AppModelBackupTests {
    private let clock = TestClock("09:00")
    private let presenter = FakePresenter()
    private let folder: TemporaryFolder

    init() throws { folder = try TemporaryFolder() }

    private func makeModel(
        stateURL: URL? = nil, backups: URL? = nil, _ edit: (inout AppSettings) -> Void = { _ in }
    ) throws -> AppModel {
        let model = try AppModel(
            database: .inMemory(), stateURL: stateURL, backups: backups ?? folder.url, clock: clock,
            calendar: Fixture.berlin)
        model.presenter = presenter
        change(model, edit)
        return model
    }

    private func change(_ model: AppModel, _ edit: (inout AppSettings) -> Void) {
        var settings = model.settings
        edit(&settings)
        model.update(settings)
    }

    private func tick(_ model: AppModel, at time: String) {
        clock.now = Fixture.at(time)
        model.send(.tick(idleSeconds: 0))
    }

    private func backups(in url: URL? = nil) -> [String] {
        Backup.all(in: url ?? folder.url, calendar: Fixture.berlin).map(\.url.lastPathComponent)
    }

    private func setWritable(_ writable: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: folder.url.path(percentEncoded: false))
    }

    @Test func backsUpAtLaunchAndThenOnceADay() throws {
        let model = try makeModel()
        #expect(model.backupFolder == folder.url)
        #expect(model.lastBackup == nil)

        model.send(.appLaunched)
        #expect(backups() == ["wamadu 2026-11-09 09.00.sqlite"])
        #expect(model.lastBackup == Fixture.at("09:00"))

        tick(model, at: "10:00")
        tick(model, at: "2026-11-10 08:59")
        #expect(backups().count == 1)

        tick(model, at: "2026-11-10 09:00")
        #expect(backups() == ["wamadu 2026-11-09 09.00.sqlite", "wamadu 2026-11-10 09.00.sqlite"])
        #expect(model.lastBackup == Fixture.at("2026-11-10 09:00"))
        #expect(model.backupFailedAt == nil)
    }

    @Test func aBackupFromAnEarlierLaunchCounts() throws {
        try makeModel().send(.appLaunched)
        clock.now = Fixture.at("15:00")

        let relaunched = try makeModel()
        #expect(relaunched.lastBackup == Fixture.at("09:00"))
        relaunched.send(.appLaunched)
        #expect(backups() == ["wamadu 2026-11-09 09.00.sqlite"])
    }

    @Test func aBackupDatedAheadDoesNotHoldBackTheNextOne() throws {
        let model = try makeModel()
        try model.database.backUp(
            to: folder.url, at: Fixture.at("2030-01-01 00:00"), keep: 30, calendar: Fixture.berlin)

        let relaunched = try makeModel()
        relaunched.send(.appLaunched)
        #expect(backups() == ["wamadu 2026-11-09 09.00.sqlite", "wamadu 2030-01-01 00.00.sqlite"])
    }

    @Test func withoutAutomaticBackupsOnlyBackUpNowWrites() throws {
        let model = try makeModel { $0.backup.automatic = false }
        model.send(.appLaunched)
        tick(model, at: "2026-11-11 09:00")
        #expect(backups().isEmpty)

        model.backUpNow()
        #expect(backups() == ["wamadu 2026-11-11 09.00.sqlite"])
        #expect(model.lastBackup == Fixture.at("2026-11-11 09:00"))
    }

    @Test func aFailedBackupKeepsTheLastGoodOneAndIsTriedAgainAfterAnHour() throws {
        defer { try? setWritable(true) }
        let model = try makeModel()
        model.send(.appLaunched)

        try setWritable(false)
        tick(model, at: "2026-11-10 09:00")
        #expect(model.backupFailedAt == Fixture.at("2026-11-10 09:00"))
        #expect(model.lastBackup == Fixture.at("09:00"))

        try setWritable(true)
        tick(model, at: "2026-11-10 09:59")
        #expect(backups().count == 1)
        #expect(model.backupFailedAt != nil)

        tick(model, at: "2026-11-10 10:00")
        #expect(backups().last == "wamadu 2026-11-10 10.00.sqlite")
        #expect(model.backupFailedAt == nil)
        #expect(model.lastBackup == Fixture.at("2026-11-10 10:00"))
    }

    @Test func anotherFolderShowsItsOwnLastBackup() throws {
        let other = try TemporaryFolder()
        let model = try makeModel()
        model.send(.appLaunched)

        change(model) { $0.backup.folder = other.url.path(percentEncoded: false) }
        #expect(model.backupFolder?.standardizedFileURL == other.url.standardizedFileURL)
        #expect(model.lastBackup == nil)

        tick(model, at: "09:05")
        #expect(backups(in: other.url) == ["wamadu 2026-11-09 09.05.sqlite"])
        #expect(backups() == ["wamadu 2026-11-09 09.00.sqlite"])
    }

    @Test func restoreBacksUpTheCurrentDataFirstAndStartsFresh() throws {
        let stateURL = folder.url.appending(path: "tracker-state.json")
        let model = try makeModel(stateURL: stateURL) { $0.backup.keep = 1 }
        _ = try model.database.createActivity(name: "Writing")
        model.send(.appLaunched)
        let saved = try #require(Backup.all(in: folder.url, calendar: Fixture.berlin).first)

        tick(model, at: "10:00")
        model.shortcut(.openCheckIn)
        model.log(.create(name: "Reading", projectId: nil))
        tick(model, at: "10:30")
        let reading = try #require(model.catalog.activities.first { $0.name == "Reading" }?.id)
        #expect(model.currentActivity == reading)
        model.statusItemClicked()
        #expect(model.panel != nil)

        let backup = try AppDatabase.readBackup(at: saved.url, calendar: Fixture.berlin)
        #expect(backup.date == Fixture.at("09:00"))
        try model.restore(backup)

        // the safety backup replaced the restored file, which was already read
        #expect(backups() == ["wamadu 2026-11-09 10.30.sqlite"])
        let safety = try AppDatabase.open(at: folder.url.appending(path: "wamadu 2026-11-09 10.30.sqlite"))
        #expect(try safety.activities().map(\.name).sorted() == ["Break", "Private", "Reading", "Writing"])
        #expect(model.lastBackup == Fixture.at("10:30"))

        #expect(try model.database.activities().map(\.name).sorted() == ["Break", "Private", "Writing"])
        #expect(model.catalog.activities.map(\.name).sorted() == ["Break", "Private", "Writing"])
        #expect(model.mode == .off)
        #expect(model.currentActivity == nil)
        #expect(model.tracker.runningSince == nil)
        #expect(model.panel == nil)
        #expect(presenter.calls.last == "hide")
        let stored = try JSONDecoder().decode(TrackerState.self, from: Data(contentsOf: stateURL))
        #expect(stored == model.tracker.state)

        tick(model, at: "10:31")
        #expect(model.mode == .tracking)
        tick(model, at: "10:46")
        #expect(model.panel == .checkIn(CheckIn(mode: .timed, span: Fixture.span("10:31", "10:46"), prefill: nil)))
        #expect(
            try model.database.blocks(in: Fixture.span("00:00", "23:59")).allSatisfy {
                $0.startedAt >= Fixture.at("10:31")
            })
    }

    /// Writing, in the backup made at launch, answered by hand at 10:00.
    private func writingAfterTheBackup() throws -> (AppModel, Int64, RestorableBackup) {
        let model = try makeModel()
        let writing = try model.database.createActivity(name: "Writing").id!
        model.send(.appLaunched)
        let saved = try #require(Backup.all(in: folder.url, calendar: Fixture.berlin).first)
        tick(model, at: "10:00")
        model.shortcut(.openCheckIn)
        model.log(.existing(writing))
        return (model, writing, try AppDatabase.readBackup(at: saved.url, calendar: Fixture.berlin))
    }

    @Test func doneForTodayStaysAfterARestore() throws {
        let (model, writing, backup) = try writingAfterTheBackup()
        model.doneForToday()

        try model.restore(backup)
        tick(model, at: "10:05")

        #expect(model.mode == .off)
        #expect(model.nowRow == .doneForToday)
        #expect(model.currentActivity == writing)
    }

    @Test func aTimedOffStaysAfterARestore() throws {
        let (model, writing, backup) = try writingAfterTheBackup()
        model.turnOff(for: 30 * 60)

        try model.restore(backup)
        tick(model, at: "10:10")
        #expect(model.mode == .off)

        tick(model, at: "10:30")
        #expect(model.mode == .tracking)
        #expect(model.currentActivity == writing)
    }

    @Test func aRunningActivityInTheBackupStaysCurrentWithoutItsRunningSpan() throws {
        let (model, writing, backup) = try writingAfterTheBackup()
        tick(model, at: "10:20")

        try model.restore(backup)
        #expect(model.tracker.runningSince == nil)
        #expect(model.currentActivity == writing)
        #expect(try model.database.blocks(in: Fixture.span("00:00", "23:59")).isEmpty)

        tick(model, at: "10:25")
        #expect(model.nowRow == .activity(id: writing))
        #expect(model.tracker.runningSince == Fixture.at("10:25"))
    }

    @Test func aRestoreWithoutTheSafetyBackupChangesNothing() throws {
        defer { try? setWritable(true) }
        let model = try makeModel()
        model.send(.appLaunched)
        let saved = try #require(Backup.all(in: folder.url, calendar: Fixture.berlin).first)
        tick(model, at: "10:00")
        model.shortcut(.openCheckIn)
        model.log(.create(name: "Reading", projectId: nil))
        let state = model.tracker.state

        let backup = try AppDatabase.readBackup(at: saved.url, calendar: Fixture.berlin)
        try setWritable(false)
        #expect(throws: (any Error).self) { try model.restore(backup) }

        #expect(try model.database.activities().contains { $0.name == "Reading" })
        #expect(model.tracker.state == state)
        #expect(model.backupFailedAt == Fixture.at("10:00"))
    }

    @Test func withoutAFolderNothingIsBackedUpAndNothingRestored() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil, clock: clock, calendar: Fixture.berlin)
        let source = try makeModel()
        source.backUpNow()
        let saved = try #require(Backup.all(in: folder.url, calendar: Fixture.berlin).first)

        model.send(.appLaunched)
        #expect(model.backupFolder == nil)
        #expect(model.lastBackup == nil)
        #expect(throws: (any Error).self) {
            try model.restore(AppDatabase.readBackup(at: saved.url, calendar: Fixture.berlin))
        }
    }
}
