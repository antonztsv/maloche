import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "wamadu", category: "model")

/// Shows the panel under the menu bar icon; the model decides what is in it.
@MainActor
public protocol PanelPresenter: AnyObject {
    var isVisible: Bool { get }
    var isKey: Bool { get }
    /// Shows fresh content; without focus the active app keeps the keyboard.
    func show(focus: Bool)
    /// Moves the visible panel along, its content and focus stay.
    func update()
    func focus()
    func hide()
    /// An action did not go through, the panel keeps its content.
    func signalFailure()
}

public enum PanelContent: Equatable, Sendable {
    case checkIn(CheckIn)
    /// Back after being away, the answer covers the span.
    case awayReturn(span: DateInterval, prefill: Int64)
    /// Back from a break, the answer runs from the end of the span.
    case breakReturn(span: DateInterval, prefill: Int64?)
    case dashboard(DashboardDay)
    /// "That's it for today" with the values of today.
    case doneForToday(DashboardDay)

    /// A question to the user, as opposed to the dashboard views.
    public var isPrompt: Bool {
        switch self {
        case .checkIn, .awayReturn, .breakReturn: true
        case .dashboard, .doneForToday: false
        }
    }
}

/// A day and its blocks as the dashboard shows them.
public struct DashboardDay: Equatable, Sendable {
    public var period: Period
    public var blocks: [Block]

    public init(period: Period, blocks: [Block]) {
        self.period = period
        self.blocks = blocks
    }
}

/// What the Now row of the dashboard shows.
public enum NowRow: Equatable, Sendable {
    case activity(id: Int64)
    case onBreak
    case off
    /// No answer yet, the row stays hidden.
    case none
}

public struct CheckIn: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Asked by the tracker, the answer covers the span.
        case timed
        /// Opened by hand, the answer starts now.
        case manual
    }

    public var mode: Mode
    /// Since the last answer when timed, since the current activity runs when opened by hand.
    public var span: DateInterval?
    public var prefill: Int64?
    /// The span is longer than one interval, the check-in offers the split view.
    public var canSplit: Bool

    public init(mode: Mode, span: DateInterval?, prefill: Int64?, canSplit: Bool = false) {
        self.mode = mode
        self.span = span
        self.prefill = prefill
        self.canSplit = canSplit
    }
}

/// Runs the tracker against the database, keeps its state on disk and tells the panel what to show.
@MainActor @Observable
public final class AppModel {
    public let database: AppDatabase
    public let builtIns: BuiltInActivities
    // ticks change the tracker every few seconds, views observe only the published values below
    @ObservationIgnored public private(set) var tracker: Tracker
    public private(set) var mode: TrackerMode = .off
    public private(set) var currentActivity: Int64?
    public private(set) var schedule = WorkSchedule.standard
    public private(set) var catalog = Catalog()
    public private(set) var panel: PanelContent?
    @ObservationIgnored public weak var presenter: (any PanelPresenter)?
    public let calendar: Calendar
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let stateURL: URL?
    /// The dashboard a prompt replaced, the panel goes back to it once the prompt is answered.
    @ObservationIgnored private var returnTo: Period?
    @ObservationIgnored private var closedByClickOutside: Date?

    public init(
        database: AppDatabase, stateURL: URL?, settings: TrackerSettings = TrackerSettings(),
        clock: any WallClock = SystemWallClock(), calendar: Calendar = .autoupdatingCurrent
    ) throws {
        self.database = database
        self.stateURL = stateURL
        self.clock = clock
        self.calendar = calendar
        builtIns = BuiltInActivities(
            breakId: try database.builtIn(.break).id!, privateId: try database.builtIn(.private).id!)
        tracker = Tracker(
            settings: settings, calendar: calendar, builtIns: builtIns, state: Self.loadState(from: stateURL))
        reloadCatalog()
        publish()
    }

    public var now: Date { clock.now }

    public func send(_ event: TrackerEvent) {
        apply(tracker.handle(event, now: clock.now))
        publish()
        saveState()
    }

    private func publish() {
        if mode != tracker.mode { mode = tracker.mode }
        if currentActivity != tracker.currentActivity { currentActivity = tracker.currentActivity }
        if schedule != tracker.settings.schedule { schedule = tracker.settings.schedule }
    }

    public func apply(_ effects: [TrackerEffect]) {
        var booked = false
        for effect in effects {
            switch effect {
            case .book(let block):
                do {
                    try database.insert(block: block)
                    booked = true
                } catch {
                    logger.error("booking failed: \(String(describing: error), privacy: .public)")
                    presenter?.signalFailure()
                }
            case .showCheckIn(let prompt):
                present(
                    .checkIn(
                        CheckIn(mode: .timed, span: prompt.span, prefill: prompt.prefill, canSplit: prompt.canSplit)))
            case .showAwayReturn(let span, let prefill):
                present(.awayReturn(span: span, prefill: prefill))
            case .showBreakReturn(let span, let prefill):
                present(.breakReturn(span: span, prefill: prefill))
            case .hidePrompt:
                if panel?.isPrompt == true { endPrompt() }
            }
        }
        guard booked else { return }
        reloadCatalog()
        if case .dashboard(let day) = panel { showDashboard(day.period) }
    }

    public var nowRow: NowRow {
        switch mode {
        case .onBreak: .onBreak
        case .off: .off
        case .tracking, .continuing: currentActivity.map { .activity(id: $0) } ?? .none
        }
    }

    /// The activity "Continue without asking" keeps logging, nil before the first answer and during a break.
    public var activityToContinue: Int64? {
        mode == .onBreak ? nil : currentActivity
    }

    /// Today's dashboard, or focus or close the visible panel.
    public func statusItemClicked() {
        // the click on the icon itself took the focus and closed the panel, it must not reopen it
        if let closed = closedByClickOutside, clock.now.timeIntervalSince(closed) < 0.5 {
            closedByClickOutside = nil
            return
        }
        reveal(.statusItem) { showToday() }
    }

    /// A click outside closes what the user opened (dashboard, done panel, check-in by hand) without booking;
    /// prompts the app showed by itself stay.
    public func panelLostFocus() {
        switch panel {
        case .dashboard, .doneForToday: break
        case .checkIn(let checkIn) where checkIn.mode == .manual: break
        default: return
        }
        hidePanel()
        closedByClickOutside = clock.now
    }

    public func shortcut(_ action: ShortcutAction) {
        guard let presenter else { return }
        switch action {
        case .openCheckIn:
            if !(presenter.isVisible && panel?.isPrompt == true) { checkIn() }
            if presenter.isVisible { presenter.focus() } else { presenter.show(focus: true) }
        case .toggleBreak:
            switch tracker.mode {
            case .tracking, .continuing: startBreak()
            case .onBreak:
                send(.openedDuringBreak)
                presenter.focus()
            case .off: break
            }
        case .openDashboard:
            // a visible prompt stays, closing it would answer it
            if presenter.isVisible, case .doneForToday = panel { showDashboard(today) }
            reveal(.shortcut) { showToday() }
        }
    }

    /// The Now row and Check In Now: the check-in by hand, during a break the break return.
    public func checkIn() {
        if tracker.mode == .onBreak {
            send(.openedDuringBreak)
        } else {
            reloadCatalog()
            let now = clock.now
            let span = tracker.runningSince.map { DateInterval(start: min($0, now), end: now) }
            showPrompt(.checkIn(CheckIn(mode: .manual, span: span, prefill: tracker.currentActivity)))
        }
    }

    /// Today's dashboard, after Done for today "That's it for today" until tracking resumes.
    private func showToday() {
        guard tracker.state.phase == .waiting, tracker.state.doneDay == calendar.startOfDay(for: now),
            let day = day(today)
        else { return showDashboard(today) }
        panel = .doneForToday(day)
        returnTo = nil
    }

    /// Paging through the days.
    public func showDashboard(_ period: Period) {
        if let day = day(period) { panel = .dashboard(day) }
        returnTo = nil
    }

    // MARK: More menu, every action closes the panel and an open prompt counts as dismissed

    public func doneForToday() {
        fromMenu(.doneForToday)
    }

    public func continueWithoutAsking(for duration: TimeInterval?) {
        guard let id = activityToContinue else { return }
        fromMenu(.continueWithoutAsking(id, for: duration))
    }

    public func stopContinuing() {
        fromMenu(.stopContinuing)
    }

    /// For the given seconds, or until the app restarts when nil.
    public func turnOff(for duration: TimeInterval?) {
        fromMenu(.turnOff(for: duration))
    }

    public func turnOn() {
        fromMenu(tracker.state.phase == .waiting ? .keepTracking : .turnOn)
    }

    /// The Keep tracking button after Done for today, after Turn off or outside the plan.
    public func keepTracking() {
        act(tracker.state.phase == .waiting ? .keepTracking : .turnOn)
    }

    private func fromMenu(_ event: TrackerEvent) {
        dismiss()
        send(event)
        hidePanel()
    }

    public func startBreak() {
        act(.startBreak)
    }

    /// Escape: a prompt goes back to the dashboard it replaced, anything else closes.
    public func close() {
        dismiss()
        endPrompt()
    }

    /// A prompt closed without an answer: a timed one counts as dismissed, the away return as Break,
    /// the break return as still on break.
    private func dismiss() {
        let closed = panel
        // without a prompt in the panel, the one the tracker ends does not close it
        panel = nil
        switch closed {
        case .checkIn(let checkIn) where checkIn.mode == .timed: send(.checkInDismissed)
        case .awayReturn: send(.awayDismissed)
        case .breakReturn: send(.stillOnBreak)
        default: break
        }
    }

    /// A timed prompt books its span, one opened by hand switches now, a return answers for the time away.
    public func log(_ choice: CheckInList.Choice) {
        guard let content = panel, content.isPrompt, let id = resolve(choice) else { return }
        logger.info("answered the panel with \(id)")
        switch content {
        case .checkIn(let checkIn): act(checkIn.mode == .timed ? .checkInAnswered(id) : .switchActivity(id))
        case .awayReturn:
            act(.awayAnswered(id == builtIns.breakId ? .break : id == builtIns.privateId ? .private : .activity(id)))
        case .breakReturn: act(.breakReturnAnswered(id))
        case .dashboard, .doneForToday: break
        }
        reloadCatalog()
    }

    /// Books the parts of a timed span, the last part runs on.
    public func log(_ split: SplitDraft) {
        guard case .checkIn(let checkIn) = panel, checkIn.mode == .timed else { return }
        guard let choices = split.choices else {
            presenter?.signalFailure()
            return
        }
        let ids = choices.compactMap(resolve)
        guard ids.count == choices.count else { return }
        act(.checkInSplit(dividers: split.dividers, activities: ids))
        reloadCatalog()
    }

    /// Uses the customer of that name or creates it; an empty customer name means none.
    public func createProject(name: String, customerName: String) throws -> Project {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WamaduError.emptyName }
        let customerName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        var customerId: Int64?
        if !customerName.isEmpty {
            let existing = try database.customers().first {
                $0.name.caseInsensitiveCompare(customerName) == .orderedSame
            }
            customerId = try (existing ?? database.createCustomer(name: customerName)).id
        }
        let project = try database.createProject(name: name, customerId: customerId)
        reloadCatalog()
        return project
    }

    /// A new name creates the activity, unless an earlier part of a split just did.
    private func resolve(_ choice: CheckInList.Choice) -> Int64? {
        switch choice {
        case .existing(let id):
            return id
        case .create(let name, let projectId):
            do {
                if let existing = Suggestions.exactMatch(for: name, in: try database.activities()) {
                    return existing.id
                }
                return try database.createActivity(name: name, projectId: projectId).id
            } catch {
                logger.error("creating an activity failed: \(String(describing: error), privacy: .public)")
                presenter?.signalFailure()
                return nil
            }
        }
    }

    /// A prompt from the tracker shows without taking the focus.
    private func present(_ content: PanelContent) {
        reloadCatalog()
        showPrompt(content)
        reveal(.timer) {}
    }

    private func showPrompt(_ content: PanelContent) {
        if case .dashboard(let day) = panel { returnTo = day.period }
        panel = content
    }

    /// Shows, focuses or closes the panel; `content` fills it when it opens.
    private func reveal(_ trigger: PanelFocus.Trigger, content: () -> Void) {
        guard let presenter else { return }
        switch PanelFocus.action(for: trigger, visible: presenter.isVisible, key: presenter.isKey) {
        case .show(let focus):
            content()
            if panel != nil { presenter.show(focus: focus) }
        case .update: presenter.update()
        case .focus: presenter.focus()
        case .close:
            dismiss()
            hidePanel()
        }
    }

    /// A user action: a dashboard stays and shows it, a prompt counts as answered and goes back to its dashboard or closes.
    /// An action the tracker ignores keeps the panel and signals it.
    private func act(_ event: TrackerEvent) {
        let content = panel
        var unchanged = tracker.state
        // without a prompt in the panel, the one the tracker ends does not close it
        if content?.isPrompt == true { panel = nil }
        send(event)
        // every user action counts as input, also one the tracker ignores
        unchanged.lastInput = tracker.state.lastInput
        guard tracker.state != unchanged else {
            panel = content
            presenter?.signalFailure()
            return
        }
        switch content {
        case .dashboard(let day): showDashboard(day.period)
        case nil: break
        case .some: endPrompt()
        }
    }

    /// Back to the dashboard the prompt replaced, else the panel closes.
    private func endPrompt() {
        if let back = returnTo { showDashboard(back) } else { hidePanel() }
    }

    private var today: Period { Period(.day, containing: now, calendar: calendar) }

    private func day(_ period: Period) -> DashboardDay? {
        do {
            return DashboardDay(period: period, blocks: try database.blocks(in: period.interval))
        } catch {
            logger.error("loading the dashboard failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func hidePanel() {
        panel = nil
        returnTo = nil
        presenter?.hide()
    }

    private func reloadCatalog() {
        do {
            let today = calendar.dateInterval(of: .day, for: clock.now) ?? DateInterval(start: clock.now, duration: 0)
            catalog = Catalog(
                activities: try database.activities(), projects: try database.projects(),
                customers: try database.customers(), todayBlocks: try database.blocks(in: today))
        } catch {
            logger.error("loading the catalog failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func saveState() {
        guard let stateURL else { return }
        do {
            try JSONEncoder().encode(tracker.state).write(to: stateURL, options: .atomic)
        } catch {
            logger.error("saving the tracker state failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func loadState(from url: URL?) -> TrackerState {
        guard let url, let data = try? Data(contentsOf: url) else { return TrackerState() }
        do {
            return try JSONDecoder().decode(TrackerState.self, from: data)
        } catch {
            logger.error("tracker state unreadable, starting fresh: \(String(describing: error), privacy: .public)")
            return TrackerState()
        }
    }
}
