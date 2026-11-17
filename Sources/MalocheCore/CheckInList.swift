import Foundation

/// The suggestions under the check-in field: what the arrow keys select and what Return logs.
public struct CheckInList: Equatable, Sendable {
    public enum Row: Equatable, Sendable {
        case create(name: String)
        case activity(Suggestion, today: Bool)
    }

    public enum Choice: Equatable, Sendable {
        case existing(Int64)
        case create(name: String, projectId: Int64?, customerId: Int64? = nil)
    }

    public static let maxRows = 6

    public private(set) var text: String
    public private(set) var rows: [Row] = []
    public private(set) var selection: Int?
    /// Grouped into today and earlier until a query filters the rows.
    public private(set) var showsSections = true
    /// The project of a new activity; setting one clears `customerId`.
    public var projectId: Int64? {
        didSet { if projectId != nil { customerId = nil } }
    }
    /// The customer of a new activity without project; setting one clears `projectId`.
    public var customerId: Int64? {
        didSet { if customerId != nil { projectId = nil } }
    }
    private let catalog: Catalog
    /// Break and Private are suggested too, below the other activities.
    private let includingBuiltIns: Bool

    public init(catalog: Catalog, prefill: Int64?, includingBuiltIns: Bool = false) {
        self.catalog = catalog
        self.includingBuiltIns = includingBuiltIns
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
        fill(top: query.isEmpty ? nil : catalog.match(for: query), query: query)
    }

    /// Without a selection either arrow selects the first row.
    public mutating func moveSelection(by offset: Int) {
        guard !rows.isEmpty else { return }
        selection = min(max((selection ?? -1) + offset, 0), rows.count - 1)
    }

    public mutating func select(_ index: Int) {
        if rows.indices.contains(index) { selection = index }
    }

    public var choice: Choice? {
        switch selection.map({ rows[$0] }) {
        case .create(let name): .create(name: name, projectId: projectId, customerId: customerId)
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

    /// Ranked suggestions for the query with `top` moved to the first row, which is selected; an empty field selects nothing.
    /// A query also offers Create: last below an exact name or the first name it starts words of, else selected on top.
    private mutating func fill(top: Activity?, query: String) {
        let usedToday = Set(catalog.usedToday)
        var ranked = catalog.suggestions(for: query, includingBuiltIns: includingBuiltIns).filter {
            $0.activity.id != top?.id
        }
        if includingBuiltIns, query.isEmpty {
            let builtIns = ranked.filter { $0.activity.kind != .regular }
            ranked = ranked.filter { $0.activity.kind == .regular }.prefix(Self.maxRows - 1 - builtIns.count) + builtIns
        }
        var suggestions = (top.map { [catalog.suggestion(for: $0)] } ?? []) + ranked
        let row = { (suggestion: Suggestion) in
            Row.activity(suggestion, today: usedToday.contains(suggestion.activity.id ?? 0))
        }
        guard !query.isEmpty else {
            rows = suggestions.prefix(Self.maxRows).map(row)
            selection = rows.isEmpty || top == nil ? nil : 0
            return
        }
        // the same name may be created for another project or customer, Break and Private never
        if let top {
            rows =
                top.kind == .regular
                ? suggestions.prefix(Self.maxRows - 1).map(row) + [.create(name: query)]
                : suggestions.prefix(Self.maxRows).map(row)
            selection = 0
            return
        }
        guard
            var best = suggestions.firstIndex(where: {
                $0.activity.names.contains { Suggestions.startsWords(of: $0, query: query) }
            })
        else {
            rows = [.create(name: query)] + suggestions.prefix(Self.maxRows - 1).map(row)
            selection = 0
            return
        }
        if best > Self.maxRows - 2 {
            suggestions.insert(suggestions.remove(at: best), at: Self.maxRows - 2)
            best = Self.maxRows - 2
        }
        rows = suggestions.prefix(Self.maxRows - 1).map(row) + [.create(name: query)]
        selection = best
    }
}
