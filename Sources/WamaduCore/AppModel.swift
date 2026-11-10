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

    public init(mode: Mode, span: DateInterval?, prefill: Int64?) {
        self.mode = mode
        self.span = span
        self.prefill = prefill
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
                reloadCatalog()
                panel = .checkIn(CheckIn(mode: .timed, span: prompt.span, prefill: prompt.prefill))
                open(.timer)
            case .showAwayReturn, .showBreakReturn:
                // TODO: show the away and break returns, an unanswered one counts as Break meanwhile
                break
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
        case .show(let focus):
            if trigger != .timer { prepareManualCheckIn() }
            if panel != nil { presenter.show(focus: focus) }
        case .update: presenter.update()
        case .focus: presenter.focus()
        case .close: close()
        }
    }

    /// Escape, or a click on the icon while the panel has the focus; a timed prompt counts as dismissed.
    public func close() {
        let closed = panel
        panel = nil
        presenter?.hide()
        if case .checkIn(let checkIn) = closed, checkIn.mode == .timed { send(.checkInDismissed) }
    }

    /// A timed prompt books its span, one opened by hand switches now.
    public func log(_ choice: CheckInList.Choice) {
        guard case .checkIn(let checkIn) = panel else { return }
        let id: Int64
        switch choice {
        case .existing(let existing):
            id = existing
        case .create(let name, let projectId):
            do {
                guard let created = try database.createActivity(name: name, projectId: projectId).id else { return }
                id = created
            } catch {
                logger.error("creating an activity failed: \(String(describing: error), privacy: .public)")
                return
            }
        }
        panel = nil
        presenter?.hide()
        logger.info("answered \(checkIn.mode == .timed ? "timed" : "manual", privacy: .public) check-in with \(id)")
        send(checkIn.mode == .timed ? .checkInAnswered(id) : .switchActivity(id))
        reloadCatalog()
    }

    public func startBreak() {
        panel = nil
        presenter?.hide()
        send(.startBreak)
    }

    private func prepareManualCheckIn() {
        // TODO: show the break return here, the check-in stands in until it exists
        if tracker.mode == .onBreak { send(.openedDuringBreak) }
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
