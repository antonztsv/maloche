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

public enum AwayAnswer: Equatable, Sendable {
    case `break`, `private`
    case activity(Int64)
}

public enum TrackerEvent: Equatable, Sendable {
    /// Sent every few seconds; idle is the time since the last keyboard or mouse input.
    case tick(idleSeconds: TimeInterval)
    /// Screen locked or Mac asleep; since is the last input.
    case systemAway(since: Date)
    case appLaunched
    case checkInAnswered(Int64)
    /// The span since the last answer split at n-1 dividers into n activities.
    case checkInSplit(dividers: [Date], activities: [Int64])
    case checkInDismissed
    /// The panel was opened by hand to change the activity.
    case switchActivity(Int64)
    case awayAnswered(AwayAnswer)
    case awayDismissed
    case startBreak
    case breakReturnAnswered(Int64)
    case stillOnBreak
    /// The menu bar icon was clicked during a break.
    case openedDuringBreak
}

public enum TrackerEffect: Equatable, Sendable {
    /// Insert the block. Re-booking a span is idempotent because a new block wins over the blocks it overlaps.
    case book(Block)
    case showAwayReturn(span: DateInterval, prefill: Int64)
    case showBreakReturn(span: DateInterval, prefill: Int64?)
    /// Close the visible prompt. Sent only when the tracker ends a prompt the user did not answer.
    case hidePrompt
}

/// Everything the tracker needs to continue after a restart.
public struct TrackerState: Codable, Equatable, Sendable {
    enum Phase: Codable, Equatable, Sendable {
        case waiting
        case tracking
        case away(since: Date)
        /// Back from away, the answer is pending while the current activity runs from `backAt`.
        case awayReturn(since: Date, backAt: Date)
        case onBreak(idleSeen: Bool)
        case breakReturn(returnAt: Date)
    }

    var phase = Phase.waiting
    /// The running activity outside breaks, before the first answer of a day the prefill.
    var current: Int64?
    var runStart = Date.distantPast
    var runSource = BlockSource.checkIn
    /// Start of the span since the last answer.
    var spanStart = Date.distantPast
    var lastInput = Date.distantPast
    var lastTick: Date?
    var lastBookAt = Date.distantPast
    var day: Date?
    var answeredDay: Date?
    /// Spans that ran without any activity, booked on the first activity named.
    var unassigned: [DateInterval] = []

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
        case .tracking, .away, .awayReturn: .tracking
        case .onBreak, .breakReturn: .onBreak
        }
    }

    public mutating func handle(_ event: TrackerEvent, now: Date) -> [TrackerEffect] {
        self.now = Self.whole(now)
        effects = []
        switch event {
        case .tick(let idle):
            if let lastTick = state.lastTick, self.now.timeIntervalSince(lastTick) > settings.awayThreshold {
                tickGap()
            }
            state.lastTick = self.now
            state.lastInput = max(state.lastInput, Self.whole(now - idle))
            advance()
        case .systemAway(let since):
            state.lastInput = max(state.lastInput, Self.whole(since))
            switch state.phase {
            case .tracking, .awayReturn: goAway(since: state.lastInput)
            default: break
            }
        case .appLaunched:
            if let lastTick = state.lastTick, self.now.timeIntervalSince(lastTick) > settings.awayThreshold {
                tickGap()
            }
            state.lastTick = self.now
            showPendingPrompt()
        default:
            state.lastInput = max(state.lastInput, self.now)
            userAction(event)
        }
        return effects
    }

    private mutating func userAction(_ event: TrackerEvent) {
        switch (event, state.phase) {
        case (.checkInAnswered(let id), .tracking):
            answer(id)
        case (.checkInSplit(let dividers, let activities), .tracking):
            let span = DateInterval(start: state.spanStart, end: now)
            guard let parts = try? SpanSplit.blocks(span: span, dividers: dividers, activities: activities)
            else { break }
            bookRun(until: span.start)
            effects += parts.map(TrackerEffect.book)
            run(parts[parts.count - 1].activityId, from: parts[parts.count - 1].startedAt, source: .split)
            answered()
        case (.switchActivity(let id), .tracking):
            bookRun(until: now)
            run(id, from: now, source: .manual)
            answered()
        case (.awayAnswered(let answer), .awayReturn(let since, let backAt)):
            answerAway(answer, since: since, backAt: backAt)
        case (.awayDismissed, .awayReturn(let since, let backAt)):
            answerAway(.break, since: since, backAt: backAt)
        case (.startBreak, .tracking), (.startBreak, .awayReturn):
            leave()
            state.phase = .onBreak(idleSeen: false)
            state.runStart = now
            state.runSource = .manual
        case (.openedDuringBreak, .onBreak):
            returnFromBreak(at: now)
        case (.breakReturnAnswered(let id), .breakReturn(let returnAt)):
            bookRun(until: returnAt)
            state.phase = .tracking
            run(id, from: returnAt, source: .checkIn)
            bookRun(until: now)
            answered()
        case (.stillOnBreak, .breakReturn):
            state.phase = .onBreak(idleSeen: false)
        default:
            break
        }
    }

    // MARK: Phases

    private mutating func advance() {
        var before: TrackerState.Phase
        repeat {
            before = state.phase
            step()
        } while state.phase != before
    }

    private mutating func step() {
        let present = now.timeIntervalSince(state.lastInput) < settings.awayThreshold
        switch state.phase {
        case .waiting:
            if present { resume(at: state.lastInput) }
        case .tracking, .awayReturn:
            if present { provisional() } else { goAway(since: state.lastInput) }
        case .away(let since):
            // idle is still short right after a lock, so back needs an input after the absence began
            guard present, state.lastInput > since else { break }
            let backAt = state.lastInput
            state.phase = .awayReturn(since: since, backAt: backAt)
            state.runStart = backAt
            state.runSource = .checkIn
            effects.append(.showAwayReturn(span: DateInterval(start: since, end: backAt), prefill: builtIns.breakId))
        case .onBreak(let idleSeen):
            if !present {
                state.phase = .onBreak(idleSeen: true)
            } else if idleSeen {
                returnFromBreak(at: state.lastInput)
            } else {
                provisional()
            }
        case .breakReturn:
            provisional()
        }
    }

    /// The app did not tick for longer than the away threshold.
    private mutating func tickGap() {
        switch state.phase {
        case .tracking, .awayReturn: goAway(since: state.lastInput)
        case .onBreak: state.phase = .onBreak(idleSeen: true)
        default: break
        }
    }

    private mutating func resume(at start: Date) {
        let day = calendar.startOfDay(for: start)
        if state.day != day { state.unassigned = [] }
        state.day = day
        state.phase = .tracking
        state.runStart = start
        state.runSource = .checkIn
        state.spanStart = start
    }

    private mutating func goAway(since: Date) {
        settleAway()
        closePrompt()
        let since = max(since, state.runStart)
        bookRun(until: since)
        state.phase = .away(since: since)
    }

    private mutating func returnFromBreak(at returnAt: Date) {
        state.phase = .breakReturn(returnAt: returnAt)
        effects.append(
            .showBreakReturn(span: DateInterval(start: state.runStart, end: returnAt), prefill: state.current))
    }

    /// Ends the running phase for a user action: a pending away question counts as Break.
    private mutating func leave() {
        settleAway()
        closePrompt()
        bookRun(until: now)
    }

    private mutating func settleAway() {
        guard case .awayReturn(let since, let backAt) = state.phase else { return }
        book(builtIns.breakId, since, backAt, source: .away)
    }

    private mutating func closePrompt() {
        switch state.phase {
        case .awayReturn, .breakReturn: effects.append(.hidePrompt)
        default: break
        }
    }

    private mutating func showPendingPrompt() {
        switch state.phase {
        case .awayReturn(let since, let backAt):
            effects.append(.showAwayReturn(span: DateInterval(start: since, end: backAt), prefill: builtIns.breakId))
        case .breakReturn(let returnAt):
            effects.append(
                .showBreakReturn(span: DateInterval(start: state.runStart, end: returnAt), prefill: state.current))
        default:
            break
        }
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

    private mutating func answerAway(_ answer: AwayAnswer, since: Date, backAt: Date) {
        state.phase = .tracking
        switch answer {
        case .break:
            book(builtIns.breakId, since, backAt, source: .away)
        case .private:
            book(builtIns.privateId, since, backAt, source: .away)
        case .activity(let id):
            book(id, since, backAt, source: .away)
            if id != state.current { run(id, from: backAt, source: .checkIn) }
        }
        bookRun(until: now)
        answered()
    }

    private mutating func answered() {
        state.spanStart = now
        state.answeredDay = calendar.startOfDay(for: now)
    }

    // MARK: Booking

    /// The activity booked for the running span.
    private var running: Int64? {
        switch state.phase {
        case .onBreak, .breakReturn: builtIns.breakId
        default: state.current
        }
    }

    private mutating func run(_ id: Int64, from start: Date, source: BlockSource) {
        if id != builtIns.breakId, id != builtIns.privateId {
            for span in state.unassigned { book(id, span.start, span.end, source: .checkIn) }
            state.unassigned = []
        }
        state.current = id
        state.runStart = start
        state.runSource = source
    }

    private mutating func provisional() {
        guard running != nil, now >= state.lastBookAt + Self.bookingPause else { return }
        bookRun(until: state.lastInput)
    }

    private mutating func bookRun(until end: Date) {
        state.lastBookAt = now
        guard end > state.runStart else { return }
        if let id = running {
            book(id, state.runStart, end, source: state.runSource)
        } else {
            state.unassigned.append(DateInterval(start: state.runStart, end: end))
        }
    }

    private mutating func book(_ id: Int64, _ start: Date, _ end: Date, source: BlockSource) {
        guard end > start else { return }
        effects.append(.book(Block(activityId: id, startedAt: start, endedAt: end, source: source)))
    }

    static func whole(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }
}
