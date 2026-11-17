import Foundation

public struct TrackerSettings: Codable, Equatable, Sendable {
    public var checkInInterval: TimeInterval
    public var awayThreshold: TimeInterval
    public var schedule: WorkSchedule

    public init(
        checkInInterval: TimeInterval = 15 * 60, awayThreshold: TimeInterval = 15 * 60,
        schedule: WorkSchedule = .standard
    ) {
        self.checkInInterval = checkInInterval
        self.awayThreshold = awayThreshold
        self.schedule = schedule
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
    case doneForToday
    /// The button in the "That's it for today" panel.
    case keepTracking
    /// Off for the given seconds, or when nil until the app restarts.
    case turnOff(for: TimeInterval?)
    case turnOn
    /// Books the activity without check-ins for the given seconds, or until stopped when nil.
    case continueWithoutAsking(Int64, for: TimeInterval?)
    case stopContinuing
}

public struct CheckInPrompt: Equatable, Sendable {
    /// Since the last answer, before the first answer of a day since the first time not booked yet.
    public var span: DateInterval
    /// What the answer books, without the absences in the span.
    public var duration: TimeInterval
    public var prefill: Int64?
    /// The span is longer than one interval and has no absence in it.
    public var canSplit: Bool

    public init(span: DateInterval, duration: TimeInterval? = nil, prefill: Int64?, canSplit: Bool) {
        self.span = span
        self.duration = duration ?? span.duration
        self.prefill = prefill
        self.canSplit = canSplit
    }
}

public enum TrackerEffect: Equatable, Sendable {
    /// Insert the block. Re-booking a span is idempotent because a new block wins over the blocks it overlaps.
    case book(Block)
    /// Show the check-in, or update the visible one and keep what the user typed.
    case showCheckIn(CheckInPrompt)
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
        /// Away during the break since the given last input, the return needs an input after it.
        case onBreak(awaySince: Date?)
        case breakReturn(returnAt: Date)
        case continuing(until: Date?)
        case off(until: Date?)
    }

    var phase = Phase.waiting
    /// The running activity outside breaks, before the first answer of a day the prefill.
    var current: Int64?
    var runStart = Date.distantPast
    var runSource = BlockSource.checkIn
    /// Start of the span since the last answer.
    var spanStart = Date.distantPast
    var lastPromptAt = Date.distantPast
    var checkInShown = false
    var lastInput = Date.distantPast
    var lastTick: Date?
    var lastBookAt = Date.distantPast
    var day: Date?
    /// The day an answer last named the current activity.
    var answeredDay: Date?
    var doneDay: Date?
    /// Turned on outside the plan, lasts until done, off or the next absence.
    var override = false
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
        case .waiting, .off: .off
        case .tracking, .away, .awayReturn: .tracking
        case .onBreak, .breakReturn: .onBreak
        case .continuing: .continuing
        }
    }

    /// The running activity, nil before the first answer of a day.
    public var currentActivity: Int64? {
        state.answeredDay != nil && state.answeredDay == state.day ? state.current : nil
    }

    /// What the check-in field starts with: the running activity, before the first answer of a day the last one.
    public var prefill: Int64? { state.current }

    /// After a merge, the running activity runs on as the target.
    public mutating func replaceActivities(_ ids: Set<Int64>, with target: Int64) {
        if let current = state.current, ids.contains(current) { state.current = target }
    }

    /// After a delete the prefill goes; a deleted running activity ends without booking and the time from `date` waits
    /// for the next answer, also while it continued without asking.
    public mutating func deleted(activities ids: Set<Int64>, at date: Date) {
        guard let current = state.current, ids.contains(current) else { return }
        let wasRunning = running == current
        state.current = nil
        guard wasRunning else { return }
        if case .continuing = state.phase { state.phase = .tracking }
        state.runStart = Self.whole(date)
        state.spanStart = state.runStart
    }

    /// After a restore: the running span, its unbooked time and a pending prompt are dropped; Done for today, Off and
    /// the override stay, the current activity too while the restored data has it.
    public mutating func restored(activities: Set<Int64>) {
        switch state.phase {
        case .waiting, .off: break
        default: state.phase = .waiting
        }
        state.checkInShown = false
        state.unassigned = []
        if let current = state.current, !activities.contains(current) { state.current = nil }
    }

    /// Since when the current activity or the break runs, nil while off or away.
    public var runningSince: Date? { isRunning ? state.runStart : nil }

    public mutating func handle(_ event: TrackerEvent, now: Date) -> [TrackerEffect] {
        self.now = Self.whole(now)
        effects = []
        switch event {
        case .tick(let idle):
            if let lastTick = state.lastTick, self.now.timeIntervalSince(lastTick) > settings.awayThreshold {
                tickGap()
            }
            state.lastTick = self.now
            state.lastInput = max(state.lastInput, Self.whole(now - max(idle, 0)))
            advance()
        case .systemAway(let since):
            state.lastInput = max(state.lastInput, min(Self.whole(since), self.now))
            switch state.phase {
            case .tracking, .awayReturn, .breakReturn: goAway(since: state.lastInput)
            case .continuing: goAway(since: self.now)
            case .onBreak: state.phase = .onBreak(awaySince: state.lastInput)
            default: break
            }
        case .appLaunched:
            if let lastTick = state.lastTick, self.now.timeIntervalSince(lastTick) > settings.awayThreshold {
                tickGap()
            }
            state.lastTick = self.now
            if state.phase == .off(until: nil) { endOff(at: self.now) }
            showPendingPrompt()
        default:
            state.lastInput = max(state.lastInput, self.now)
            userAction(event)
        }
        return effects
    }

    private mutating func userAction(_ event: TrackerEvent) {
        switch (event, state.phase) {
        case (.checkInAnswered(builtIns.breakId), .tracking), (.switchActivity(builtIns.breakId), _):
            userAction(.startBreak)
        case (.breakReturnAnswered(builtIns.breakId), _):
            userAction(.stillOnBreak)
        case (.awayAnswered(.activity(builtIns.breakId)), _):
            userAction(.awayAnswered(.break))
        case (.checkInAnswered(let id), .tracking):
            answer(id)
        case (.checkInDismissed, .tracking):
            state.checkInShown = false
            // before the first answer the day starts over, earlier use stays private
            if currentActivity == nil {
                state.unassigned = []
                resume(at: now)
            }
        case (.checkInSplit(let dividers, let activities), .tracking):
            let spans = checkInSpans
            guard spans.count == 1, let span = spans.first,
                let parts = try? SpanSplit.blocks(span: span, dividers: dividers, activities: activities)
            else { break }
            bookRun(until: span.start)
            // the parts cover the unassigned spans, run must not book them again over the parts
            if running == nil { state.unassigned = [] }
            effects += parts.map(TrackerEffect.book)
            if let work = parts.last(where: { $0.activityId != builtIns.breakId }) {
                run(work.activityId, from: work.startedAt, source: .split)
            }
            if let last = parts.last, last.activityId == builtIns.breakId {
                state.phase = .onBreak(awaySince: nil)
                state.runStart = last.startedAt
                state.runSource = .split
            }
            answered()
        case (.switchActivity, .away), (.continueWithoutAsking, .away):
            break
        case (.switchActivity(let id), _):
            begin(id, source: .manual, phase: .tracking)
        case (.continueWithoutAsking(let id, let duration), _):
            begin(id, source: .continued, phase: .continuing(until: duration.map { Self.whole(now + $0) }))
        case (.stopContinuing, .continuing):
            finishContinuing(at: now)
        case (.awayAnswered(let answer), .awayReturn(let since, let backAt)):
            answerAway(answer, since: since, backAt: backAt)
        case (.awayDismissed, .awayReturn(let since, let backAt)):
            answerAway(currentActivity == nil ? nil : .break, since: since, backAt: backAt)
        case (.startBreak, .tracking), (.startBreak, .awayReturn), (.startBreak, .continuing):
            leave()
            state.phase = .onBreak(awaySince: nil)
            state.runStart = now
            state.runSource = .manual
        case (.openedDuringBreak, .onBreak):
            returnFromBreak(at: now)
        case (.openedDuringBreak, .breakReturn):
            showPendingPrompt()
        case (.breakReturnAnswered(let id), .breakReturn(let returnAt)):
            bookRun(until: returnAt)
            state.phase = .tracking
            run(id, from: returnAt, source: .checkIn)
            bookRun(until: now)
            answered()
        case (.stillOnBreak, .breakReturn):
            state.phase = .onBreak(awaySince: nil)
        case (.doneForToday, _):
            state.doneDay = isRunning ? state.day : calendar.startOfDay(for: now)
            stop(.waiting)
        case (.turnOff(let duration), _):
            stop(.off(until: duration.map { Self.whole(now + $0) }))
        case (.turnOn, .waiting), (.turnOn, .off), (.keepTracking, .waiting), (.keepTracking, .off):
            turnOn()
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
        if isRunning, dayOver {
            endDay()
            return
        }
        switch state.phase {
        case .waiting:
            guard present, state.doneDay != calendar.startOfDay(for: now),
                let plan = settings.schedule.workday(on: now, calendar: calendar),
                state.lastInput >= plan.start, now < plan.end
            else { break }
            resume(at: state.lastInput)
        case .off(let until):
            guard let until, now >= until else { break }
            endOff(at: until)
        case .tracking, .awayReturn, .breakReturn:
            guard present else {
                goAway(since: state.lastInput)
                break
            }
            provisional()
            if state.phase == .tracking { checkInIfDue() }
        case .away(let since):
            if dayOver {
                state.phase = .waiting
                break
            }
            // idle is still short right after a lock, so back needs an input after the absence began
            guard present, state.lastInput > since else { break }
            let backAt = state.lastInput
            let overrideEnds = !insidePlan(backAt) || calendar.startOfDay(for: backAt) != state.day
            if state.override, overrideEnds {
                state.override = false
                state.phase = .waiting
                break
            }
            state.override = false
            state.phase = .awayReturn(since: since, backAt: backAt)
            state.runStart = backAt
            state.runSource = .checkIn
            effects.append(.showAwayReturn(span: DateInterval(start: since, end: backAt), prefill: builtIns.breakId))
        case .onBreak(let awaySince):
            if !present {
                if awaySince == nil { state.phase = .onBreak(awaySince: state.lastInput) }
            } else if let awaySince, state.lastInput > awaySince {
                returnFromBreak(at: state.lastInput)
            } else {
                provisional()
            }
        case .continuing(let until):
            if let until, now >= until { finishContinuing(at: until) } else { provisional() }
        }
    }

    /// The app did not tick for longer than the away threshold.
    private mutating func tickGap() {
        switch state.phase {
        case .tracking, .awayReturn, .breakReturn: goAway(since: state.lastInput)
        case .continuing: goAway(since: state.lastTick ?? now)
        case .onBreak where dayOver: endDay()
        case .onBreak: state.phase = .onBreak(awaySince: state.lastInput)
        case .off(let until?) where until <= now:
            // the end passed while the app did not run, tracking restarts with the next input
            state.phase = .waiting
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
        state.lastPromptAt = start
        state.checkInShown = false
        state.lastInput = max(state.lastInput, start)
    }

    private mutating func turnOn() {
        resume(at: now)
        state.override = !insidePlan(now)
        state.doneDay = nil
    }

    private mutating func endOff(at start: Date) {
        if insidePlan(start) { resume(at: start) } else { state.phase = .waiting }
    }

    /// Starts running `id` now, from a running phase or from off.
    private mutating func begin(_ id: Int64, source: BlockSource, phase: TrackerState.Phase) {
        if isRunning { leave() } else { turnOn() }
        state.phase = phase
        run(id, from: now, source: source)
        answered()
    }

    private mutating func finishContinuing(at end: Date) {
        bookRun(until: end)
        resume(at: end)
    }

    private mutating func stop(_ phase: TrackerState.Phase) {
        if isRunning { leave() }
        state.phase = phase
        state.override = false
    }

    /// At the plan end the day ends with the last input.
    private mutating func endDay() {
        settleReturns()
        bookRun(until: min(runEnd, planEnd ?? runEnd))
        state.phase = .waiting
    }

    private mutating func goAway(since: Date) {
        settleReturns()
        let since = max(since, state.runStart)
        bookRun(until: since)
        state.phase = .away(since: since)
    }

    private mutating func returnFromBreak(at returnAt: Date) {
        state.phase = .breakReturn(returnAt: returnAt)
        effects.append(
            .showBreakReturn(span: DateInterval(start: state.runStart, end: returnAt), prefill: state.current))
    }

    /// Ends the running phase for a user action.
    private mutating func leave() {
        settleReturns()
        bookRun(until: now)
    }

    /// Closes the prompt; a pending away question counts as Break once the day has an answer, a pending break return
    /// ends the break at the return and the activity before the break runs on from there.
    private mutating func settleReturns() {
        closePrompt()
        switch state.phase {
        case .awayReturn(let since, let backAt):
            if currentActivity != nil { book(builtIns.breakId, since, backAt, source: .away) }
        case .breakReturn(let returnAt):
            bookRun(until: returnAt)
            state.phase = .tracking
            state.runStart = returnAt
            state.runSource = .checkIn
        default:
            break
        }
    }

    private mutating func closePrompt() {
        switch state.phase {
        case .awayReturn, .breakReturn: effects.append(.hidePrompt)
        default: if state.checkInShown { effects.append(.hidePrompt) }
        }
        state.checkInShown = false
    }

    private mutating func checkInIfDue() {
        guard now >= state.lastPromptAt + settings.checkInInterval else { return }
        state.lastPromptAt = now
        state.checkInShown = true
        effects.append(.showCheckIn(checkInPrompt))
    }

    private var checkInPrompt: CheckInPrompt {
        let spans = checkInSpans
        let duration = spans.reduce(0) { $0 + $1.duration }
        return CheckInPrompt(
            span: DateInterval(start: spans[0].start, end: now), duration: duration, prefill: state.current,
            canSplit: spans.count == 1 && duration > settings.checkInInterval)
    }

    /// What a timed check-in books: the span since the last answer, before the first answer of a day the time not
    /// booked yet.
    private var checkInSpans: [DateInterval] {
        unbooked(until: now) ?? [DateInterval(start: state.spanStart, end: now)]
    }

    /// Before the first answer of a day while running, the spans no activity was named for up to `end`, merged in
    /// order; absences and the time answered as Break or Private lie between them.
    func unbooked(until end: Date) -> [DateInterval]? {
        guard isRunning, running == nil else { return nil }
        let spans = state.unassigned + [DateInterval(start: min(state.runStart, end), end: end)]
        return spans.sorted { $0.start < $1.start }.reduce(into: []) { merged, span in
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else {
                merged.append(span)
            }
        }
    }

    private mutating func showPendingPrompt() {
        switch state.phase {
        case .tracking where state.checkInShown:
            effects.append(.showCheckIn(checkInPrompt))
        case .awayReturn(let since, let backAt):
            effects.append(.showAwayReturn(span: DateInterval(start: since, end: backAt), prefill: builtIns.breakId))
        case .breakReturn(let returnAt):
            effects.append(
                .showBreakReturn(span: DateInterval(start: state.runStart, end: returnAt), prefill: state.current))
        default:
            break
        }
    }

    private var isRunning: Bool {
        switch state.phase {
        case .waiting, .off, .away: false
        default: true
        }
    }

    private var planEnd: Date? {
        state.day.flatMap { settings.schedule.workday(on: $0, calendar: calendar)?.end }
    }

    private var dayOver: Bool {
        !state.override && now >= (planEnd ?? .distantPast)
    }

    private func insidePlan(_ date: Date) -> Bool {
        settings.schedule.workday(on: date, calendar: calendar).map { $0.start <= date && date < $0.end } ?? false
    }

    // MARK: Answers

    private mutating func answer(_ id: Int64) {
        if id == running {
            bookRun(until: now)
        } else {
            let span = state.spanStart
            let cut = running == nil ? state.runStart : Self.whole(span + now.timeIntervalSince(span) / 2)
            bookRun(until: cut)
            run(id, from: cut, source: .checkIn)
            bookRun(until: now)
        }
        answered()
    }

    /// Without an answer the absence stays free.
    private mutating func answerAway(_ answer: AwayAnswer?, since: Date, backAt: Date) {
        state.phase = .tracking
        switch answer {
        case .break:
            book(builtIns.breakId, since, backAt, source: .away)
        case .private:
            book(builtIns.privateId, since, backAt, source: .away)
        case .activity(let id):
            book(id, since, backAt, source: .away)
            if id != running { run(id, from: backAt, source: .checkIn) }
        case nil:
            break
        }
        bookRun(until: now)
        answered()
    }

    private mutating func answered() {
        state.spanStart = now
        state.lastPromptAt = now
        state.checkInShown = false
    }

    // MARK: Booking

    /// The activity booked for the running span.
    private var running: Int64? {
        switch state.phase {
        case .onBreak, .breakReturn: builtIns.breakId
        default: currentActivity
        }
    }

    private mutating func run(_ id: Int64, from start: Date, source: BlockSource) {
        if id != builtIns.breakId, id != builtIns.privateId {
            for span in state.unassigned { book(id, span.start, span.end, source: .checkIn) }
            state.unassigned = []
        }
        state.current = id
        state.answeredDay = state.day
        state.runStart = start
        state.runSource = source
    }

    private mutating func provisional() {
        guard running != nil, now >= state.lastBookAt + Self.bookingPause else { return }
        bookRun(until: runEnd)
    }

    /// Continuing counts time without input, every other phase up to the last input.
    private var runEnd: Date {
        if case .continuing = state.phase { return now }
        return state.lastInput
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
