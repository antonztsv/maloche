import Foundation
import Testing

@testable import WamaduCore

enum Fixture {
    static let writing: Int64 = 1
    static let reading: Int64 = 2
    static let meeting: Int64 = 3
    static let breakId: Int64 = 100
    static let privateId: Int64 = 101
    static let names: [Int64: String] = [1: "Writing", 2: "Reading", 3: "Meeting", 100: "Break", 101: "Private"]
    static let builtIns = BuiltInActivities(breakId: breakId, privateId: privateId)
    /// For tests of other rules, check-ins never come due.
    static let noCheckIns = TrackerSettings(checkInInterval: 7 * 24 * 3600)

    static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// "08:15" or "08:15:30" on Monday 2026-11-09, "2026-11-10 08:15" on another day, Berlin time.
    static func at(_ text: String) -> Date {
        var numbers = text.split { !$0.isNumber }.map { Int($0)! }
        if numbers.count < 5 { numbers = [2026, 11, 9] + numbers }
        let components = DateComponents(
            year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4],
            second: numbers.count > 5 ? numbers[5] : 0)
        return berlin.date(from: components)!
    }

    static func span(_ start: String, _ end: String) -> DateInterval {
        DateInterval(start: at(start), end: at(end))
    }

    /// "08:15", with seconds when set, prefixed with month and day when not on 2026-11-09.
    static func clock(_ date: Date) -> String {
        let parts = berlin.dateComponents([.month, .day, .hour, .minute, .second], from: date)
        var text = String(format: "%02d:%02d", parts.hour!, parts.minute!)
        if parts.second! != 0 { text += String(format: ":%02d", parts.second!) }
        if parts.month! != 11 || parts.day! != 9 {
            text = String(format: "%02d-%02d ", parts.month!, parts.day!) + text
        }
        return text
    }
}

/// Drives a tracker with a simulated clock and user, applying bookings like `AppDatabase.insert(block:)`.
struct Harness {
    var tracker: Tracker
    var now: Date
    var lastInput: Date
    var blocks: [Block] = []
    var prompts: [TrackerEffect] = []
    var bookings = 0
    private var nextId: Int64 = 1

    init(at time: String = "08:00", current: Int64? = Fixture.writing, settings: TrackerSettings = TrackerSettings()) {
        var state = TrackerState()
        state.current = current
        tracker = Tracker(settings: settings, calendar: Fixture.berlin, builtIns: Fixture.builtIns, state: state)
        now = Fixture.at(time)
        lastInput = now
    }

    /// One tick at the current time, idle since the simulated last input.
    mutating func tick() {
        record(.tick(idleSeconds: now.timeIntervalSince(lastInput)))
    }

    /// Ticks every minute up to `time`; the user works throughout unless `idle` is set.
    mutating func pass(to time: String, idle: Bool = false) {
        let end = Fixture.at(time)
        while now < end {
            now = min(now + 60, end)
            if !idle { lastInput = now }
            tick()
        }
    }

    /// A user action at the current time, which also counts as input.
    mutating func send(_ event: TrackerEvent) {
        lastInput = now
        record(event)
    }

    mutating func record(_ event: TrackerEvent) {
        for effect in tracker.handle(event, now: now) {
            guard case .book(let block) = effect else {
                prompts.append(effect)
                continue
            }
            book(block)
        }
    }

    /// Restarts the app from the persisted state.
    mutating func relaunch() throws {
        let state = try JSONDecoder().decode(TrackerState.self, from: JSONEncoder().encode(tracker.state))
        tracker = Tracker(
            settings: tracker.settings, calendar: Fixture.berlin, builtIns: Fixture.builtIns, state: state)
        record(.appLaunched)
    }

    mutating func takePrompts() -> [TrackerEffect] {
        defer { prompts = [] }
        return prompts
    }

    var timeline: [String] {
        blocks.map { "\(Fixture.names[$0.activityId]!) \(Fixture.clock($0.startedAt))-\(Fixture.clock($0.endedAt))" }
    }

    private mutating func book(_ block: Block) {
        bookings += 1
        #expect(block.startedAt < block.endedAt, "empty block \(block)")
        #expect(Self.isWhole(block.startedAt) && Self.isWhole(block.endedAt), "fractional block \(block)")
        let changes = Timeline.changes(inserting: block, into: blocks)
        blocks.removeAll { block in block.id.map(changes.deletedIds.contains) ?? false }
        for updated in changes.updated {
            blocks[blocks.firstIndex { $0.id == updated.id }!] = updated
        }
        for var inserted in changes.inserted {
            inserted.id = nextId
            nextId += 1
            blocks.append(inserted)
        }
        blocks.sort { $0.startedAt < $1.startedAt }
    }

    static func isWhole(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.rounded(.down) == date.timeIntervalSinceReferenceDate
    }
}
