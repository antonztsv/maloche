import Foundation

/// The choices in the welcome window, starting from the settings; all chosen days share one plan.
public struct Welcome: Equatable, Sendable {
    /// `Calendar` weekdays, 1 is Sunday.
    public var days: Set<Int>
    public var plan: WorkSchedule.Plan
    public var checkInInterval: TimeInterval
    public var checkForUpdates: Bool

    public init(settings: AppSettings, calendar: Calendar) {
        days = Set(settings.schedule.plans.keys)
        plan = settings.schedule.firstPlan(calendar: calendar)
        checkInInterval = settings.checkInInterval
        checkForUpdates = settings.checkForUpdates
    }
}

extension AppModel {
    /// Until Start or closing; time already booked belongs to someone using the app, also without stored settings.
    public var welcomeDue: Bool {
        !settings.welcomeDone && (try? database.hasBlocks()) == false
    }

    /// Start applies the choices, closing keeps the settings; either way the welcome is done.
    public func finishWelcome(_ welcome: Welcome?) {
        var settings = settings
        if let welcome {
            settings.schedule = WorkSchedule(
                plans: Dictionary(uniqueKeysWithValues: welcome.days.map { ($0, welcome.plan) }))
            settings.checkInInterval = welcome.checkInInterval
            settings.checkForUpdates = welcome.checkForUpdates
        }
        settings.welcomeDone = true
        update(settings)
    }
}
