import Foundation

public struct TrackerSettings: Codable, Equatable, Sendable {
    public var checkInInterval: TimeInterval
    public var awayThreshold: TimeInterval

    public init(checkInInterval: TimeInterval = 15 * 60, awayThreshold: TimeInterval = 15 * 60) {
        self.checkInInterval = checkInInterval
        self.awayThreshold = awayThreshold
    }
}

public struct BuiltInActivities: Codable, Equatable, Sendable {
    public var breakId: Int64
    public var privateId: Int64

    public init(breakId: Int64, privateId: Int64) {
        self.breakId = breakId
        self.privateId = privateId
    }
}

/// What the menu bar icon shows.
public enum TrackerMode: Sendable {
    case tracking, onBreak, continuing, off
}

public enum TrackerEvent: Equatable, Sendable {
    /// Sent every few seconds; idle is the time since the last keyboard or mouse input.
    case tick(idleSeconds: TimeInterval)
    case checkInAnswered(Int64)
    case checkInDismissed
    /// The panel was opened by hand to change the activity.
    case switchActivity(Int64)
}

public enum TrackerEffect: Equatable, Sendable {
    /// Insert the block. Re-booking a span is idempotent because a new block wins over the blocks it overlaps.
    case book(Block)
}

/// Everything the tracker needs to continue after a restart.
public struct TrackerState: Codable, Equatable, Sendable {
    enum Phase: Codable, Equatable, Sendable {
        case waiting
        case tracking
    }

    var phase = Phase.waiting
    /// The running activity, before the first answer of a day the prefill.
    var current: Int64?
    var runStart = Date.distantPast
    var runSource = BlockSource.checkIn
    /// Start of the span since the last answer.
    var spanStart = Date.distantPast
    var lastInput = Date.distantPast
    var lastBookAt = Date.distantPast
    var day: Date?
    var answeredDay: Date?

    public init() {}
}

/// Decides what gets booked and when to ask; the app executes the effects and persists `state`.
public struct Tracker: Sendable {
    public private(set) var state: TrackerState
    public var settings: TrackerSettings
    private let calendar: Calendar
    private let builtIns: BuiltInActivities
    private var now = Date.distantPast
    private var effects: [TrackerEffect] = []

    private static let bookingPause: TimeInterval = 60

    public init(
        settings: TrackerSettings, calendar: Calendar, builtIns: BuiltInActivities, state: TrackerState = .init()
    ) {
        self.settings = settings
        self.calendar = calendar
        self.builtIns = builtIns
        self.state = state
    }

    public var mode: TrackerMode {
        switch state.phase {
        case .waiting: .off
        case .tracking: .tracking
        }
    }

    public mutating func handle(_ event: TrackerEvent, now: Date) -> [TrackerEffect] {
        self.now = Self.whole(now)
        effects = []
        switch event {
        case .tick(let idle):
            state.lastInput = max(state.lastInput, Self.whole(now - idle))
            advance()
        case .checkInAnswered(let id):
            guard state.phase == .tracking else { break }
            answer(id)
        case .checkInDismissed:
            break
        case .switchActivity(let id):
            guard state.phase == .tracking else { break }
            bookRun(until: self.now)
            run(id, from: self.now, source: .manual)
            answered()
        }
        return effects
    }

    // MARK: Phases

    private mutating func advance() {
        switch state.phase {
        case .waiting:
            resume(at: state.lastInput)
        case .tracking:
            provisional()
        }
    }

    private mutating func resume(at start: Date) {
        state.phase = .tracking
        state.day = calendar.startOfDay(for: start)
        state.runStart = start
        state.runSource = .checkIn
        state.spanStart = start
    }

    // MARK: Answers

    private mutating func answer(_ id: Int64) {
        if id == state.current {
            bookRun(until: now)
        } else {
            let firstOfDay = state.answeredDay != calendar.startOfDay(for: now) || state.current == nil
            let span = state.spanStart
            let cut = firstOfDay ? span : Self.whole(span + now.timeIntervalSince(span) / 2)
            bookRun(until: cut)
            run(id, from: cut, source: .checkIn)
            bookRun(until: now)
        }
        answered()
    }

    private mutating func answered() {
        state.spanStart = now
        state.answeredDay = calendar.startOfDay(for: now)
    }

    // MARK: Booking

    private mutating func run(_ id: Int64, from start: Date, source: BlockSource) {
        state.current = id
        state.runStart = start
        state.runSource = source
    }

    private mutating func provisional() {
        guard now >= state.lastBookAt + Self.bookingPause else { return }
        bookRun(until: state.lastInput)
    }

    private mutating func bookRun(until end: Date) {
        state.lastBookAt = now
        guard let id = state.current, end > state.runStart else { return }
        effects.append(.book(Block(activityId: id, startedAt: state.runStart, endedAt: end, source: state.runSource)))
    }

    static func whole(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }
}
