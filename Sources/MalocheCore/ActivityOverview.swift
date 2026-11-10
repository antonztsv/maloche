import Foundation

/// The Manage Activities window: customers with their projects in the sidebar, the regular activities in the table.
public struct ActivityOverview: Sendable {
    public enum Filter: Hashable, Sendable {
        case all
        case customer(Int64)
        case project(Int64)
        /// Without customer, also through a project without one.
        case noCustomer
        case archived
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public var activity: Activity
        public var projectName: String?
        /// The project's customer, else the activity's own.
        public var customerName: String?
        public var thisMonth: TimeInterval
        public var id: Int64 { activity.id ?? 0 }
    }

    /// A customer with its projects, nil for the projects without customer.
    public struct Group: Equatable, Sendable {
        public var customer: Customer?
        public var projects: [Project]
    }

    public let catalog: Catalog
    /// Most recently used first, never used last.
    private let all: [Row]
    private let customerIds: [Int64: Int64]

    /// `thisMonth` is the work per activity of the current calendar month.
    public init(catalog: Catalog, thisMonth: [ActivityTotal]) {
        self.catalog = catalog
        let projects = catalog.projects.byId
        let customers = catalog.customers.byId
        let work = Dictionary(
            thisMonth.compactMap { total in total.activity.id.map { ($0, total.duration) } }, uniquingKeysWith: +)
        let regular = catalog.activities.filter { $0.kind == .regular }
        customerIds = Dictionary(
            regular.compactMap { activity in
                activity.id.flatMap { id in activity.customerId(projects: projects).map { (id, $0) } }
            }, uniquingKeysWith: { first, _ in first })
        all =
            regular
            .map { activity in
                Row(
                    activity: activity, projectName: activity.projectId.flatMap { projects[$0]?.name },
                    customerName: activity.customerId(projects: projects).flatMap { customers[$0]?.name },
                    thisMonth: activity.id.flatMap { work[$0] } ?? 0)
            }
            .sorted { first, second in
                let (a, b) = (first.activity, second.activity)
                let (usedA, usedB) = (a.lastUsedAt ?? .distantPast, b.lastUsedAt ?? .distantPast)
                if usedA != usedB { return usedA > usedB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// Every customer by name, then the projects without customer.
    public var groups: [Group] {
        (catalog.customers.map(Optional.some) + [nil]).map { customer in
            Group(customer: customer, projects: catalog.projects.filter { $0.customerId == customer?.id })
        }
    }

    public func count(_ filter: Filter) -> Int {
        all.count { includes($0, filter) }
    }

    /// The rows of the filter the query matches like the check-in does.
    public func rows(_ filter: Filter, query: String = "") -> [Row] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { row in
            includes(row, filter)
                && Suggestions.matches(
                    needle, name: row.activity.name, projectName: row.projectName, customerName: row.customerName)
        }
    }

    private func includes(_ row: Row, _ filter: Filter) -> Bool {
        guard row.activity.archived == (filter == .archived) else { return false }
        return switch filter {
        case .all, .archived: true
        case .customer(let id): customerIds[row.id] == id
        case .project(let id): row.activity.projectId == id
        case .noCustomer: customerIds[row.id] == nil
        }
    }

    /// Where a new activity goes with the filter selected.
    public static func placement(for filter: Filter) -> (projectId: Int64?, customerId: Int64?) {
        switch filter {
        case .project(let id): (id, nil)
        case .customer(let id): (nil, id)
        case .all, .noCustomer, .archived: (nil, nil)
        }
    }

    /// The customer of a new project with the filter selected.
    public func customerOfNewProject(for filter: Filter) -> Int64? {
        switch filter {
        case .customer(let id): id
        case .project(let id): catalog.project(id)?.customerId
        case .all, .noCustomer, .archived: nil
        }
    }
}
