import Foundation

public struct Suggestion: Equatable, Sendable {
    public var activity: Activity
    public var projectName: String?
    public var customerName: String?
}

public enum Suggestions {
    /// Today's activities first (most recent use today first), then by last use, never used last, ties by name.
    /// The query matches activity, project or customer names, ignoring case and diacritics.
    public static func ranked(
        query: String, activities: [Activity], projects: [Project], customers: [Customer], usedToday: [Int64],
        includingBuiltIns: Bool = false
    ) -> [Suggestion] {
        let projectsById = projects.byId
        let customersById = customers.byId
        let todayRank = Dictionary(usedToday.enumerated().map { ($1, $0) }) { first, _ in first }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return
            activities
            .filter { !$0.archived && (includingBuiltIns || $0.kind == .regular) }
            .map { activity in
                Suggestion(
                    activity: activity, projectName: activity.projectId.flatMap { projectsById[$0]?.name },
                    customerName: activity.customerId(projects: projectsById).flatMap { customersById[$0]?.name })
            }
            .filter { suggestion in
                needle.isEmpty
                    || [suggestion.activity.name, suggestion.projectName, suggestion.customerName].contains {
                        $0?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                    || startsWords(of: suggestion.activity.name, query: needle)
            }
            .sorted { first, second in
                let (a, b) = (first.activity, second.activity)
                let (todayA, todayB) = (a.id.flatMap { todayRank[$0] } ?? .max, b.id.flatMap { todayRank[$0] } ?? .max)
                if todayA != todayB { return todayA < todayB }
                let (usedA, usedB) = (a.lastUsedAt ?? .distantPast, b.lastUsedAt ?? .distantPast)
                if usedA != usedB { return usedA > usedB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// Every word of the query starts a word of the name, ignoring case and diacritics, like Spotlight.
    public static func startsWords(of name: String, query: String) -> Bool {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        let typed = query.split { !$0.isLetter && !$0.isNumber }
        return !typed.isEmpty
            && typed.allSatisfy { part in
                words.contains {
                    $0.range(of: part, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
                }
            }
    }

    /// The non-archived regular activity named like the trimmed query, ignoring case; nil means the UI offers "Create".
    public static func exactMatch(for query: String, in activities: [Activity]) -> Activity? {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return activities.first {
            !$0.archived && $0.kind == .regular && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
