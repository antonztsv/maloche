import Foundation

/// Activities, projects and customers with today's blocks, as the panel shows them.
public struct Catalog: Equatable, Sendable {
    public var activities: [Activity]
    public var projects: [Project]
    public var customers: [Customer]
    public var todayBlocks: [Block]

    public init(
        activities: [Activity] = [], projects: [Project] = [], customers: [Customer] = [], todayBlocks: [Block] = []
    ) {
        self.activities = activities
        self.projects = projects
        self.customers = customers
        self.todayBlocks = todayBlocks
    }

    /// Activities booked today, most recently used first.
    public var usedToday: [Int64] {
        var seen = Set<Int64>()
        return todayBlocks.sorted { $0.endedAt > $1.endedAt }.map(\.activityId).filter { seen.insert($0).inserted }
    }

    public func activity(_ id: Int64?) -> Activity? {
        id.flatMap { id in activities.first { $0.id == id } }
    }

    public func project(_ id: Int64?) -> Project? {
        id.flatMap { id in projects.first { $0.id == id } }
    }

    public func customer(_ id: Int64?) -> Customer? {
        id.flatMap { id in customers.first { $0.id == id } }
    }

    /// The project's customer when the activity has a project, otherwise its own.
    public func customer(of activity: Activity) -> Customer? {
        customer(activity.customerId(projects: projects.byId))
    }

    func suggestions(for query: String, includingBuiltIns: Bool = false) -> [Suggestion] {
        Suggestions.ranked(
            query: query, activities: activities, projects: projects, customers: customers, usedToday: usedToday,
            includingBuiltIns: includingBuiltIns)
    }

    func suggestion(for activity: Activity) -> Suggestion {
        Suggestion(
            activity: activity, projectName: project(activity.projectId)?.name,
            customerName: customer(of: activity)?.name)
    }

    /// The activity named like the query ignoring case: Break or Private under either name, else of several the first
    /// suggested, else the most recently used archived one.
    func match(for query: String) -> Activity? {
        let same = { (name: String) in name.caseInsensitiveCompare(query) == .orderedSame }
        let named = { (activity: Activity) in same(activity.name) }
        return activities.first { $0.kind != .regular && $0.names.contains(where: same) }
            ?? suggestions(for: "").map(\.activity).first(where: named)
            ?? activities.filter { $0.archived && named($0) }.max {
                ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast)
            }
    }
}
