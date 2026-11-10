import Foundation
import Testing

@testable import WamaduCore

@Suite struct SuggestionsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86400)
    }

    private let customers = [
        Customer(id: 1, name: "Acme", colorIndex: 0), Customer(id: 2, name: "Globex", colorIndex: 1),
    ]
    private let projects = [Project(id: 10, name: "Website", customerId: 1)]

    private var activities: [Activity] {
        [
            Activity(id: 1, name: "Writing", projectId: 10, lastUsedAt: daysAgo(3)),
            Activity(id: 2, name: "Code Review", customerId: 2, lastUsedAt: daysAgo(1)),
            Activity(id: 3, name: "Überarbeitung"),
            Activity(id: 4, name: "Reading", lastUsedAt: daysAgo(2)),
            Activity(id: 5, name: "Old Stuff", archived: true, lastUsedAt: daysAgo(0.5)),
            Activity(id: 6, name: "Break", kind: .break, lastUsedAt: daysAgo(0.1)),
            Activity(id: 7, name: "Private", kind: .private),
            Activity(id: 8, name: "Admin"),
        ]
    }

    private func names(
        _ query: String, usedToday: [Int64] = [4, 1], activities: [Activity]? = nil, includingBuiltIns: Bool = false
    ) -> [String] {
        Suggestions.ranked(
            query: query, activities: activities ?? self.activities, projects: projects, customers: customers,
            usedToday: usedToday, includingBuiltIns: includingBuiltIns
        ).map(\.activity.name)
    }

    @Test func withoutQueryTodayComesFirstThenLastUsedThenNeverUsedByName() {
        #expect(names("") == ["Reading", "Writing", "Code Review", "Admin", "Überarbeitung"])
    }

    @Test func whitespaceQueryCountsAsNoQuery() {
        #expect(names("  \n ") == names(""))
    }

    @Test func todayOrderFollowsMostRecentUseToday() {
        #expect(names("", usedToday: [1, 4]).prefix(2) == ["Writing", "Reading"])
    }

    @Test func builtInsAreIncludedOnRequest() {
        #expect(
            names("", includingBuiltIns: true) == [
                "Reading", "Writing", "Break", "Code Review", "Admin", "Private", "Überarbeitung",
            ])
    }

    @Test func archivedActivitiesAreExcludedEvenWhenUsedToday() {
        #expect(!names("", usedToday: [5]).contains("Old Stuff"))
        #expect(names("old").isEmpty)
    }

    @Test func queryIgnoresCaseDiacriticsAndSurroundingWhitespace() {
        #expect(names("uber") == ["Überarbeitung"])
        #expect(names(" ÜBER ") == ["Überarbeitung"])
        #expect(names("WRIT") == ["Writing"])
    }

    @Test func queryMatchesProjectAndCustomerNames() {
        #expect(names("web") == ["Writing"])
        #expect(names("acme") == ["Writing"])
        #expect(names("globex") == ["Code Review"])
    }

    @Test func matchesKeepTheSameOrder() {
        #expect(names("in") == ["Reading", "Writing", "Admin"])
    }

    @Test func suggestionsCarryProjectAndCustomerNames() {
        let suggestions = Suggestions.ranked(
            query: "", activities: activities, projects: projects, customers: customers, usedToday: [])
        let writing = suggestions.first { $0.activity.id == 1 }
        #expect(writing?.projectName == "Website")
        #expect(writing?.customerName == "Acme")
        let review = suggestions.first { $0.activity.id == 2 }
        #expect(review?.projectName == nil)
        #expect(review?.customerName == "Globex")
        let reading = suggestions.first { $0.activity.id == 4 }
        #expect(reading?.projectName == nil)
        #expect(reading?.customerName == nil)
    }

    @Test func equalLastUseIsOrderedByName() {
        let tied = [
            Activity(id: 1, name: "Beta", lastUsedAt: daysAgo(1)),
            Activity(id: 2, name: "alpha", lastUsedAt: daysAgo(1)),
            Activity(id: 3, name: "Gamma", lastUsedAt: daysAgo(0.5)),
            Activity(id: 4, name: "Delta"),
            Activity(id: 5, name: "charlie"),
        ]
        #expect(names("", usedToday: [], activities: tied) == ["Gamma", "alpha", "Beta", "charlie", "Delta"])
    }

    @Test func exactMatchIgnoresCaseAndWhitespaceAndFindsArchived() {
        #expect(Suggestions.exactMatch(for: "  writing ", in: activities)?.id == 1)
        #expect(Suggestions.exactMatch(for: "Writ", in: activities) == nil)
        #expect(Suggestions.exactMatch(for: "old stuff", in: activities)?.id == 5)
        #expect(Suggestions.exactMatch(for: "", in: activities) == nil)
    }

    @Test func exactMatchSkipsBuiltIns() {
        #expect(Suggestions.exactMatch(for: "break", in: activities) == nil)
        #expect(Suggestions.exactMatch(for: "Private", in: activities) == nil)
    }
}
