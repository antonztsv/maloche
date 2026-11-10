import Foundation

/// The choices in the welcome window, starting from the settings; all chosen days share one plan.
public struct Welcome: Equatable, Sendable {
    /// `Calendar` weekdays, 1 is Sunday.
    public var days: Set<Int>
    public var plan: WorkSchedule.Plan
    public var checkInInterval: TimeInterval

    public init(settings: AppSettings, calendar: Calendar) {
        days = Set(settings.schedule.plans.keys)
        plan = settings.schedule.firstPlan(calendar: calendar)
        checkInInterval = settings.checkInInterval
    }
}

extension AppModel {
    /// Start applies the choices, closing keeps the settings; either way the welcome is done.
    public func finishWelcome(_ welcome: Welcome?) {
        var settings = settings
        if let welcome {
            settings.schedule = WorkSchedule(
                plans: Dictionary(uniqueKeysWithValues: welcome.days.map { ($0, welcome.plan) }))
            settings.checkInInterval = welcome.checkInInterval
        }
        settings.welcomeDone = true
        update(settings)
    }
}
