import Foundation
import Testing

@testable import WamaduCore

/// S8: the sidebar and the table of the Manage Activities window.
@Suite struct ActivityOverviewTests {
    private static func daysAgo(_ days: Double) -> Date {
        Fixture.at("12:00").addingTimeInterval(-days * 86400)
    }

    private static let review = Activity(id: 1, name: "Code Review", projectId: 10, lastUsedAt: daysAgo(0))
    private static let weekly = Activity(id: 4, name: "Weekly", customerId: 2, lastUsedAt: daysAgo(1))

    private let overview = ActivityOverview(
        catalog: Catalog(
            activities: [
                review,
                Activity(id: 2, name: "Kickoff", projectId: 10, lastUsedAt: daysAgo(5)),
                Activity(id: 3, name: "Backups", projectId: 11),
                weekly,
                Activity(id: 5, name: "Writing", lastUsedAt: daysAgo(2)),
                Activity(id: 6, name: "Tooling", projectId: 13, lastUsedAt: daysAgo(3)),
                Activity(id: 7, name: "Old Stuff", projectId: 10, archived: true, lastUsedAt: daysAgo(1)),
                Activity(id: 100, name: "Break", kind: .break, lastUsedAt: daysAgo(0)),
                Activity(id: 101, name: "Private", kind: .private),
            ],
            projects: [
                Project(id: 13, name: "Internal", customerId: nil), Project(id: 11, name: "Maintenance", customerId: 1),
                Project(id: 10, name: "Relaunch", customerId: 1), Project(id: 12, name: "Shop", customerId: 2),
            ],
            customers: [
                Customer(id: 1, name: "Acme", colorIndex: 0), Customer(id: 2, name: "Northwind", colorIndex: 1),
            ]
        ),
        thisMonth: [
            ActivityTotal(activity: review, duration: 38 * 3600 + 15 * 60),
            ActivityTotal(activity: weekly, duration: 30 * 60),
        ])

    private func names(_ filter: ActivityOverview.Filter, _ query: String = "") -> [String] {
        overview.rows(filter, query: query).map(\.activity.name)
    }

    @Test func theSidebarListsEachCustomerWithItsProjectsThenProjectsWithoutCustomer() {
        #expect(overview.groups.map { $0.customer?.name } == ["Acme", "Northwind", nil])
        #expect(
            overview.groups.map { $0.projects.map(\.name) } == [["Maintenance", "Relaunch"], ["Shop"], ["Internal"]])
    }

    @Test func countsLeaveOutBreakPrivateAndArchivedActivitiesExceptInArchived() {
        #expect(overview.count(.all) == 6)
        #expect(overview.count(.customer(1)) == 3)
        #expect(overview.count(.project(10)) == 2)
        #expect(overview.count(.customer(2)) == 1)
        #expect(overview.count(.project(12)) == 0)
        #expect(overview.count(.noCustomer) == 2)
        #expect(overview.count(.project(13)) == 1)
        #expect(overview.count(.archived) == 1)
    }

    @Test func rowsAreMostRecentlyUsedFirstNeverUsedLast() {
        #expect(names(.all) == ["Code Review", "Weekly", "Writing", "Tooling", "Kickoff", "Backups"])
        #expect(names(.customer(1)) == ["Code Review", "Kickoff", "Backups"])
        #expect(names(.noCustomer) == ["Writing", "Tooling"])
        #expect(names(.archived) == ["Old Stuff"])
    }

    @Test func rowsCarryProjectCustomerAndThisMonthsWork() {
        let rows = overview.rows(.all)
        #expect(rows.map(\.id) == [1, 4, 5, 6, 2, 3])
        #expect(rows.map(\.projectName) == ["Relaunch", nil, nil, "Internal", "Relaunch", "Maintenance"])
        #expect(rows.map(\.customerName) == ["Acme", "Northwind", nil, nil, "Acme", "Acme"])
        let thisMonth: [TimeInterval] = [38 * 3600 + 15 * 60, 30 * 60, 0, 0, 0, 0]
        #expect(rows.map(\.thisMonth) == thisMonth)
        #expect(rows.map(\.activity.lastUsedAt) == [0, 1, 2, 3, 5].map(Self.daysAgo) + [nil])
    }

    @Test func searchMatchesLikeTheCheckInWithinTheFilter() {
        #expect(names(.all, "acme") == ["Code Review", "Kickoff", "Backups"])
        #expect(names(.all, " relaunch ") == ["Code Review", "Kickoff"])
        #expect(names(.all, "co re") == ["Code Review"])
        #expect(names(.noCustomer, "acme").isEmpty)
        #expect(names(.archived, "old") == ["Old Stuff"])
        #expect(names(.all, "break").isEmpty)
    }

    @Test func aNewActivityGoesToTheSelectedProjectOrCustomer() {
        let placements = [ActivityOverview.Filter.project(10), .customer(2), .all, .noCustomer, .archived].map {
            ActivityOverview.placement(for: $0)
        }
        #expect(placements.map(\.projectId) == [10, nil, nil, nil, nil])
        #expect(placements.map(\.customerId) == [nil, 2, nil, nil, nil])
    }

    @Test func aNewProjectGoesToTheSelectedCustomer() {
        #expect(overview.customerOfNewProject(for: .customer(1)) == 1)
        #expect(overview.customerOfNewProject(for: .project(12)) == 2)
        #expect(overview.customerOfNewProject(for: .project(13)) == nil)
        #expect(overview.customerOfNewProject(for: .all) == nil)
    }
}
