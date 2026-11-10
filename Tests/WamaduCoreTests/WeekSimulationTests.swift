import Foundation
import GRDB
import Testing

@testable import WamaduCore

/// Weeks of use driven like `PresenceMonitor`, with sleep, a weekend and the end of daylight saving time.
@MainActor @Suite struct WeekSimulationTests {
    @Test func twoWeeksOfUseKeepTheDataSoundAndTheStateAndMemoryFlat() throws {
        weak var model: AppModel?
        weak var presenter: FakePresenter?
        do {
            let simulation = try SimulatedUse()
            try simulation.week(from: "2026-10-19", firstUse: true)
            try simulation.check(week: "2026-10-19")
            try simulation.checkDaylightSavingSunday()
            let firstWeek = try simulation.storage()
            #expect(
                try simulation.backupNames() == [
                    "wamadu 2026-10-22 08.10.sqlite", "wamadu 2026-10-23 08.10.sqlite",
                    "wamadu 2026-10-25 01.50.sqlite",
                ])
            let residentBefore = residentSize()

            try simulation.week(from: "2026-10-26", firstUse: false)
            try simulation.check(week: "2026-10-26")
            let secondWeek = try simulation.storage()
            let residentAfter = residentSize()

            #expect(simulation.presenter.failures == 0)
            #expect(simulation.model.backupFailedAt == nil)
            #expect(simulation.maxUnassigned == 1)
            #expect(simulation.maxStateSize < 1024)
            // the booking pause re-books the running span at most once a minute, blocks follow the answers
            #expect(abs(secondWeek.stored - 2 * firstWeek.stored) <= 1)
            #expect(secondWeek.stored <= simulation.actions / 4)
            #expect(secondWeek.inserted <= simulation.trackedMinutes + 2 * simulation.actions)
            #expect(
                try simulation.backupNames() == [
                    "wamadu 2026-10-29 08.10.sqlite", "wamadu 2026-10-30 08.10.sqlite",
                    "wamadu 2026-11-01 01.50.sqlite",
                ])
            #expect(residentAfter < residentBefore + (32 << 20), "resident \(residentBefore) -> \(residentAfter)")
            model = simulation.model
            presenter = simulation.presenter
        }
        #expect(model == nil)
        #expect(presenter == nil)
    }

    private func residentSize() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        #expect(result == KERN_SUCCESS)
        return info.resident_size
    }
}

/// A Mac and its user: ticks every 5 seconds while the Mac is awake, prompts answered as the script says.
@MainActor
private final class SimulatedUse {
    let clock = TestClock("08:00")
    let presenter = FakePresenter()
    let database: AppDatabase
    let folder: TemporaryFolder
    let settingsStore = MemorySettingsStore()
    private(set) var model: AppModel!
    /// Script times are local times on this day.
    private var day = Date.distantPast
    /// The last tick in whole seconds, the clock runs a seeded fraction of a second later.
    private var time = Date.distantPast
    private var fraction: TimeInterval = 0
    private var seed: UInt64 = 55
    private var lastInput = Date.distantPast
    private(set) var ticks = 0
    private(set) var actions = 0
    private(set) var maxUnassigned = 0
    private(set) var maxStateSize = 0
    /// Spans with tracking on, all inside the plan except those turned on by hand.
    private var windows: [(interval: DateInterval, offPlan: Bool)] = []
    private var expected: [Date: [String: String]] = [:]

    private var stateURL: URL { folder.url.appending(path: "tracker-state.json") }
    private var backups: URL { folder.url.appending(path: "Backups", directoryHint: .isDirectory) }

    init() throws {
        database = try .inMemory()
        folder = try TemporaryFolder()
        for name in ["Writing", "Reading", "Meeting"] { _ = try database.createActivity(name: name) }
        var settings = AppSettings()
        settings.backup.keep = 3
        settings.save(to: settingsStore)
    }

    var trackedMinutes: Int { Int(windows.reduce(0) { $0 + $1.interval.duration } / 60) }

    // MARK: The week

    func week(from first: String, firstUse: Bool) throws {
        let start = Fixture.at("\(first) 00:00")
        func on(_ offset: Int) { day = Fixture.berlin.date(byAdding: .day, value: offset, to: start)! }
        on(0)
        if firstUse { try launch(at: at("08:00")) } else { wake(at: at("08:00")) }
        try monday()
        on(1)
        try tuesday()
        on(2)
        try wednesday()
        on(3)
        try thursday()
        on(4)
        try friday()
        on(6)
        try sunday()
    }

    /// Nothing runs before the first answer, also when Sunday ended with Reading.
    private func monday() throws {
        work(until: at("08:10"))
        back(at: at("08:30"))
        answer("Break")
        work(until: at("09:45"), on: "Review")
        work(until: at("10:00"), on: "Writing")
        work(until: at("12:00"), on: "Writing")
        back(at: at("12:45"))
        answer("Break")
        work(until: at("13:45"), on: "Writing")
        work(until: at("14:00"))
        dismiss()
        work(until: at("17:50"), on: "Writing")
        lockScreen()
        tracked(at("08:00"), at("17:50"))
        try dayEnds(booking: ["Review": "1:32:30", "Writing": "7:12:30", "Break": "1:05:00"])
    }

    /// The return before the first answer is dismissed, its absence stays free.
    private func tuesday() throws {
        wake(at: at("08:10"))
        work(until: at("08:20"))
        back(at: at("08:50"))
        dismiss()
        work(until: at("09:05"))
        if case .checkIn(let checkIn) = model.panel {
            #expect(checkIn.span?.start == at("08:10") && checkIn.duration == 25 * 60 && !checkIn.canSplit)
        } else {
            Issue.record("no check-in at 09:05")
        }
        work(until: at("09:25"), on: "Reading")
        work(until: at("09:30"))
        act { $0.shortcut(.openCheckIn) }
        answer("Meeting")
        work(until: at("09:45"), on: "Meeting")
        work(until: at("10:30"))
        split(at: ["10:05"], into: ["Meeting", "Writing"])
        work(until: at("12:30"), on: "Writing")
        act { $0.startBreak() }
        back(at: at("13:15"))
        answer("Writing")
        work(until: at("14:00"), on: "Writing")
        act { $0.continueWithoutAsking(for: 3600) }
        work(until: at("14:10"))
        idle(until: at("14:50"))
        work(until: at("15:00"))
        #expect(model.panel == nil)
        work(until: at("16:00"), on: "Writing")
        act { $0.turnOff(for: 1800) }
        work(until: at("16:30"))
        #expect(model.panel == nil)
        work(until: at("17:40"), on: "Writing")
        lockScreen()
        idle(until: at("18:30"))
        lockScreen()
        tracked(at("08:10"), at("08:20"))
        tracked(at("08:50"), at("16:00"))
        tracked(at("16:30"), at("17:40"))
        try dayEnds(booking: ["Reading": "0:50:00", "Meeting": "0:35:00", "Writing": "6:20:00", "Break": "0:45:00"])
    }

    private func wednesday() throws {
        wake(at: at("08:05"))
        work(until: at("09:05"), on: "Writing")
        work(until: at("10:00"), on: "Reading")
        lockScreen()
        back(at: at("11:00"))
        answer("Meeting")
        work(until: at("12:15"), on: "Reading")
        back(at: at("13:15"))
        answer("Private")
        work(until: at("15:00"), on: "Reading")
        back(at: at("15:20"))
        dismiss()
        work(until: at("17:00"), on: "Reading")
        act { $0.doneForToday() }
        work(until: at("17:30"))
        #expect(model.panel == nil)
        tracked(at("08:05"), at("17:00"))
        try dayEnds(
            booking: [
                "Writing": "1:07:30", "Reading": "5:20:00", "Meeting": "1:07:30", "Private": "1:00:00",
                "Break": "0:20:00",
            ])
    }

    /// Starts after a shutdown, the state comes from the saved file.
    private func thursday() throws {
        try launch(at: at("07:50"))
        work(until: at("07:55"))
        idle(until: at("08:02"))
        work(until: at("09:02"), on: "Writing")
        work(until: at("09:17"))
        dismiss()
        work(until: at("09:32"))
        dismiss()
        work(until: at("09:47"))
        split(at: ["09:20", "09:35"], into: ["Writing", "Reading", "Review"])
        work(until: at("10:47"), on: "Review")
        work(until: at("11:02"), on: "Break")
        work(until: at("11:20"))
        #expect(model.panel == nil)
        act { $0.shortcut(.toggleBreak) }
        answer("Writing")
        work(until: at("12:50"), on: "Writing")
        lockScreen()
        wake(at: at("13:40"))
        answer("Break")
        work(until: at("17:40"), on: "Writing")
        lockScreen()
        tracked(at("08:02"), at("17:40"))
        try dayEnds(booking: ["Writing": "6:48:00", "Reading": "0:15:00", "Review": "1:27:00", "Break": "1:08:00"])
    }

    /// The Mac stayed awake overnight with the screen locked; after lunch the ticks no longer fall on the plan end.
    private func friday() throws {
        idle(until: at("08:30"))
        work(until: at("08:45"), on: "Meeting")
        act { $0.continueWithoutAsking(for: nil) }
        idle(until: at("09:45"))
        work(until: at("10:00"))
        #expect(model.panel == nil)
        act { $0.stopContinuing() }
        work(until: at("12:00"), on: "Writing")
        act { $0.continueWithoutAsking(for: 2 * 3600) }
        work(until: at("12:30"))
        lockScreen()
        wake(at: at("13:00:02"))
        answer("Break")
        work(until: at("18:20"), on: "Writing")
        lockScreen()
        tracked(at("08:30"), at("18:00"))
        try dayEnds(booking: ["Meeting": "1:37:30", "Writing": "7:22:28", "Break": "0:30:02"])
    }

    /// Saturday without use; Sunday from 01:50 for 90 minutes, across the end of daylight saving time in the first week.
    private func sunday() throws {
        let start = at("01:50")
        wake(at: start)
        act { $0.statusItemClicked() }
        act { $0.keepTracking() }
        act { $0.panelLostFocus() }
        work(until: start + 90 * 60, on: "Reading")
        act { $0.doneForToday() }
        work(until: start + 95 * 60)
        lockScreen()
        tracked(start, start + 90 * 60, offPlan: true)
        try dayEnds(booking: ["Reading": "1:30:00"])
    }

    // MARK: The Mac and the user

    private func at(_ text: String) -> Date {
        let parts = text.split(separator: ":").map { Int($0)! } + [0]
        return Fixture.berlin.date(bySettingHour: parts[0], minute: parts[1], second: parts[2], of: day)!
    }

    private func tick(at date: Date, input: Bool) {
        time = date
        clock.now = date + fraction
        if input { lastInput = clock.now }
        // one pool per tick as on the run loop, the atomic state write autoreleases
        autoreleasepool { model.send(.tick(idleSeconds: clock.now.timeIntervalSince(lastInput))) }
        ticks += 1
        maxUnassigned = max(maxUnassigned, model.tracker.state.unassigned.count)
    }

    /// In use up to `end`, timed check-ins answered with the activity or left open without one.
    private func work(until end: Date, on activity: String? = nil) {
        while time < end {
            tick(at: min(time + 5, end), input: true)
            if let activity, case .checkIn(let checkIn) = model.panel, checkIn.mode == .timed { answer(activity) }
        }
    }

    /// Awake without input until just before `end`.
    private func idle(until end: Date) {
        while time + 5 < end { tick(at: time + 5, input: false) }
    }

    /// Back at `end`, the return question shows.
    private func back(at end: Date) {
        idle(until: end)
        work(until: end)
    }

    /// Screen locked or Mac asleep, as `PresenceMonitor` reports it.
    private func lockScreen() {
        model.send(.systemAway(since: lastInput))
    }

    /// The tick timer starts at a new fraction of a second after a wake or launch.
    private func nextFraction() -> TimeInterval {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return TimeInterval(seed >> 11) / 0x1p53
    }

    private func wake(at date: Date) {
        fraction = nextFraction()
        tick(at: date, input: true)
    }

    /// The app starts from the saved state, the one before must be gone.
    private func launch(at date: Date) throws {
        weak let previous = model
        model = nil
        #expect(previous == nil)
        fraction = nextFraction()
        clock.now = date + fraction
        model = try AppModel(
            database: database, stateURL: stateURL, settingsStore: settingsStore, backups: backups, clock: clock,
            calendar: Fixture.berlin)
        model.presenter = presenter
        model.send(.appLaunched)
        tick(at: date, input: true)
    }

    private func act(_ action: (AppModel) -> Void) {
        lastInput = clock.now
        actions += 1
        autoreleasepool { action(model) }
    }

    private func answer(_ activity: String) {
        #expect(model.panel?.isPrompt == true, "nothing to answer at \(Fixture.clock(time))")
        let choice = id(activity).map(CheckInList.Choice.existing) ?? .create(name: activity, projectId: nil)
        act { $0.log(choice) }
    }

    private func dismiss() {
        #expect(model.panel?.isPrompt == true, "nothing to dismiss at \(Fixture.clock(time))")
        act { $0.close() }
    }

    private func split(at dividers: [String], into activities: [String]) {
        guard case .checkIn(let checkIn) = model.panel, let span = checkIn.span else {
            Issue.record("nothing to split at \(Fixture.clock(time))")
            return
        }
        let parts = activities.map { CheckInList(catalog: model.catalog, prefill: id($0)) }
        var draft = SplitDraft(span: span, first: parts[0], second: parts[1])
        for part in parts.dropFirst(2) { draft.addPart(part) }
        for (index, divider) in dividers.enumerated() { draft.moveDivider(index, to: at(divider)) }
        act { $0.log(draft) }
    }

    private func id(_ activity: String) -> Int64? {
        model.catalog.activities.first { $0.name == activity }?.id
    }

    // MARK: Checks

    private func tracked(_ start: Date, _ end: Date, offPlan: Bool = false) {
        windows.append((DateInterval(start: start, end: end), offPlan))
    }

    /// Records the day's booked totals and checks the saved state, at most a minute behind in the last tick and input.
    private func dayEnds(booking totals: [String: String]) throws {
        expected[day] = totals
        let data = try Data(contentsOf: stateURL)
        var saved = try JSONDecoder().decode(TrackerState.self, from: data)
        let live = model.tracker.state
        #expect(try #require(live.lastTick).timeIntervalSince(try #require(saved.lastTick)) < 60)
        #expect(live.lastInput.timeIntervalSince(saved.lastInput) < 60)
        saved.lastTick = live.lastTick
        saved.lastInput = live.lastInput
        #expect(saved == live)
        maxStateSize = max(maxStateSize, data.count)
    }

    /// No overlaps, every block inside a tracked span, every span booked without a gap, totals per local day as
    /// scripted.
    func check(week monday: String) throws {
        let days = (0..<7).map { offset in
            let noon = Fixture.berlin.date(byAdding: .day, value: offset, to: Fixture.at("\(monday) 12:00"))!
            return Fixture.berlin.dateInterval(of: .day, for: noon)!
        }
        let week = DateInterval(start: days[0].start, end: days[6].end)
        let blocks = try database.blocks(in: week)
        let names = Dictionary(uniqueKeysWithValues: try database.activities().map { ($0.id!, $0.name) })
        for (block, next) in zip(blocks, blocks.dropFirst()) {
            #expect(block.endedAt <= next.startedAt, "\(block) overlaps \(next)")
        }
        let windows = windows.filter { week.contains($0.interval.start) }
        for block in blocks {
            #expect(
                windows.contains { $0.interval.start <= block.startedAt && block.endedAt <= $0.interval.end },
                "booked outside tracking: \(Fixture.clock(block.startedAt))-\(Fixture.clock(block.endedAt))")
        }
        for (window, offPlan) in windows {
            #expect(blocks.reduce(0) { $0 + overlap($1.interval, window) } == window.duration, "gap in \(window)")
            let plan = model.schedule.interval(on: window.start, calendar: Fixture.berlin)
            #expect(offPlan || plan.map { $0.start <= window.start && window.end <= $0.end } == true)
        }
        for day in days {
            var totals: [String: TimeInterval] = [:]
            for block in blocks { totals[names[block.activityId]!, default: 0] += overlap(block.interval, day) }
            #expect(totals.filter { $0.value > 0 }.mapValues(text) == expected[day.start] ?? [:], "\(day)")
        }
    }

    /// The Sunday of the first week has 25 hours and its use runs from 01:50 summer time to 02:20 winter time.
    func checkDaylightSavingSunday() throws {
        let sunday = Fixture.berlin.dateInterval(of: .day, for: Fixture.at("2026-10-25 12:00"))!
        #expect(sunday.duration == 25 * 3600)
        let blocks = try database.blocks(in: sunday)
        #expect(
            blocks.map { "\(Fixture.clock($0.startedAt))-\(Fixture.clock($0.endedAt))" } == ["10-25 01:50-10-25 02:20"])
        #expect(blocks.map(\.interval.duration) == [90 * 60])
    }

    /// Blocks stored and rows ever inserted into the block table.
    func storage() throws -> (stored: Int, inserted: Int) {
        try database.dbQueue.read { db in
            (
                try Block.fetchCount(db),
                try Int.fetchOne(db, sql: "SELECT seq FROM sqlite_sequence WHERE name = 'block'") ?? 0
            )
        }
    }

    func backupNames() throws -> [String] {
        Backup.all(in: backups, calendar: Fixture.berlin).map(\.url.lastPathComponent)
    }

    private func overlap(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
    }

    private func text(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds)
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
