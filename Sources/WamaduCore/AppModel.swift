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
}

public enum PanelContent: Equatable, Sendable {
    case checkIn(CheckIn)
    /// Back after being away, the answer covers the span.
    case awayReturn(span: DateInterval, prefill: Int64)
    /// Back from a break, the answer runs from the end of the span.
    case breakReturn(span: DateInterval, prefill: Int64?)
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
    public private(set) var tracker: Tracker
    public private(set) var catalog = Catalog()
    public private(set) var panel: PanelContent?
    @ObservationIgnored public weak var presenter: (any PanelPresenter)?
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let stateURL: URL?

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
    }

    public var now: Date { clock.now }

    public func send(_ event: TrackerEvent) {
        apply(tracker.handle(event, now: clock.now))
        saveState()
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
                panel = nil
                presenter?.hide()
            }
        }
        if booked { reloadCatalog() }
    }

    /// What a click on the menu bar icon opens.
    public func statusItemClicked() {
        open(.statusItem)
    }

    public func open(_ trigger: PanelFocus.Trigger) {
        guard let presenter else { return }
        switch PanelFocus.action(for: trigger, visible: presenter.isVisible, key: presenter.isKey) {
        case .show where trigger != .timer && tracker.mode == .onBreak:
            // the break return opens like a timed prompt, then takes the focus
            send(.openedDuringBreak)
            presenter.focus()
        case .show(let focus):
            if trigger != .timer { prepareManualCheckIn() }
            if panel != nil { presenter.show(focus: focus) }
        case .update: presenter.update()
        case .focus: presenter.focus()
        case .close: close()
        }
    }

    /// Escape, or a click on the icon while the panel has the focus: a timed prompt counts as dismissed,
    /// the away return as Break, the break return as still on break.
    public func close() {
        let closed = panel
        panel = nil
        presenter?.hide()
        switch closed {
        case .checkIn(let checkIn) where checkIn.mode == .timed: send(.checkInDismissed)
        case .awayReturn: send(.awayDismissed)
        case .breakReturn: send(.stillOnBreak)
        default: break
        }
    }

    /// A timed prompt books its span, one opened by hand switches now, a return answers for the time away.
    public func log(_ choice: CheckInList.Choice) {
        guard let content = panel, let id = resolve(choice) else { return }
        panel = nil
        presenter?.hide()
        logger.info("answered the panel with \(id)")
        switch content {
        case .checkIn(let checkIn): send(checkIn.mode == .timed ? .checkInAnswered(id) : .switchActivity(id))
        case .awayReturn:
            send(
                .awayAnswered(
                    id == builtIns.breakId ? .break : id == builtIns.privateId ? .private : .activity(id)))
        case .breakReturn: send(.breakReturnAnswered(id))
        }
        reloadCatalog()
    }

    /// Books the parts of a timed span, the last part runs on.
    public func log(_ split: SplitDraft) {
        guard case .checkIn(let checkIn) = panel, checkIn.mode == .timed, let choices = split.choices else { return }
        let ids = choices.compactMap(resolve)
        guard ids.count == choices.count else { return }
        panel = nil
        presenter?.hide()
        send(.checkInSplit(dividers: split.dividers, activities: ids))
        reloadCatalog()
    }

    public func startBreak() {
        panel = nil
        presenter?.hide()
        send(.startBreak)
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
                return nil
            }
        }
    }

    private func present(_ content: PanelContent) {
        reloadCatalog()
        panel = content
        open(.timer)
    }

    private func prepareManualCheckIn() {
        reloadCatalog()
        let now = clock.now
        let span = tracker.runningSince.map { DateInterval(start: min($0, now), end: now) }
        panel = .checkIn(CheckIn(mode: .manual, span: span, prefill: tracker.currentActivity))
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
