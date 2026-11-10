import Foundation

/// The suggestions under the check-in field: what the arrow keys select and what Return logs.
public struct CheckInList: Equatable, Sendable {
    public enum Row: Equatable, Sendable {
        case create(name: String)
        case activity(Suggestion, today: Bool)
    }

    public enum Choice: Equatable, Sendable {
        case existing(Int64)
        case create(name: String, projectId: Int64?)
    }

    public static let maxRows = 6

    public private(set) var text: String
    public private(set) var rows: [Row] = []
    public private(set) var selection: Int?
    /// Grouped into today and earlier until a query filters the rows.
    public private(set) var showsSections = true
    /// The project of a new activity.
    public var projectId: Int64?
    private let catalog: Catalog

    public init(catalog: Catalog, prefill: Int64?) {
        self.catalog = catalog
        let activity = catalog.activity(prefill)
        text = activity?.name ?? ""
        fill(top: activity, query: "")
    }

    /// Unchanged text keeps the list, text fields write their value back when they take the focus.
    public mutating func setText(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        showsSections = query.isEmpty
        let match = query.isEmpty ? nil : catalog.match(for: query)
        fill(top: match, query: query)
        if !query.isEmpty, match == nil {
            rows = Array(([.create(name: query)] + rows).prefix(Self.maxRows))
            selection = 0
        }
    }

    public mutating func moveSelection(by offset: Int) {
        guard let selection else { return }
        self.selection = min(max(selection + offset, 0), rows.count - 1)
    }

    public mutating func select(_ index: Int) {
        if rows.indices.contains(index) { selection = index }
    }

    public var choice: Choice? {
        switch selection.map({ rows[$0] }) {
        case .create(let name): .create(name: name, projectId: projectId)
        case .activity(let suggestion, _): suggestion.activity.id.map(Choice.existing)
        case nil: nil
        }
    }

    public var isCreating: Bool {
        if case .create = selection.map({ rows[$0] }) { true } else { false }
    }

    /// The selected activity when the field carries its name.
    public var fieldMatch: Suggestion? {
        guard case .activity(let suggestion, _) = selection.map({ rows[$0] }),
            suggestion.activity.name.caseInsensitiveCompare(text.trimmingCharacters(in: .whitespacesAndNewlines))
                == .orderedSame
        else { return nil }
        return suggestion
    }

    /// Ranked suggestions for the query with `top` moved to the first row, which is selected.
    private mutating func fill(top: Activity?, query: String) {
        let usedToday = Set(catalog.usedToday)
        let ranked = catalog.suggestions(for: query).filter { $0.activity.id != top?.id }
        let suggestions = (top.map { [catalog.suggestion(for: $0)] } ?? []) + ranked
        rows = suggestions.prefix(Self.maxRows).map { .activity($0, today: usedToday.contains($0.activity.id ?? 0)) }
        selection = rows.isEmpty ? nil : 0
    }
}
