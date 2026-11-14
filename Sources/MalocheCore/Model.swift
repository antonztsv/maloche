import Foundation
import GRDB

public struct Customer: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64?
    public var name: String
    public var colorIndex: Int

    public init(id: Int64? = nil, name: String, colorIndex: Int) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
    }
}

public enum CustomerColor: Int, CaseIterable, Sendable {
    case blue, purple, orange, teal, pink, green, indigo, brown

    /// The lowest unused index, or the least used one (lowest on tie) when all are taken.
    public static func nextIndex(used: [Int]) -> Int {
        let counts = allCases.map { color in used.count { $0 == color.rawValue } }
        return counts.indices.min { counts[$0] < counts[$1] } ?? 0
    }
}

public struct Project: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64?
    public var name: String
    public var customerId: Int64?

    public init(id: Int64? = nil, name: String, customerId: Int64?) {
        self.id = id
        self.name = name
        self.customerId = customerId
    }
}

public enum ActivityKind: String, Codable, Sendable {
    case regular
    case `break`
    case `private`

    /// The name Break and Private are stored under, the app may show another.
    var storedName: String? {
        switch self {
        case .regular: nil
        case .break: "Break"
        case .private: "Private"
        }
    }
}

public struct Activity: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64?
    public var name: String
    public var projectId: Int64?
    public var customerId: Int64?
    public var kind: ActivityKind
    public var archived: Bool
    public var lastUsedAt: Date?

    public init(
        id: Int64? = nil, name: String, projectId: Int64? = nil, customerId: Int64? = nil,
        kind: ActivityKind = .regular, archived: Bool = false, lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.projectId = projectId
        self.customerId = customerId
        self.kind = kind
        self.archived = archived
        self.lastUsedAt = lastUsedAt
    }
}

extension Activity {
    /// Its name and, for Break and Private, the stored one.
    var names: [String] { [name] + [kind.storedName].compactMap { $0 } }
}

public enum BlockSource: String, Codable, Sendable {
    case checkIn, manual, split, away, continued, imported
}

public struct Block: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64?
    public var activityId: Int64
    public var startedAt: Date
    public var endedAt: Date
    public var source: BlockSource

    public init(id: Int64? = nil, activityId: Int64, startedAt: Date, endedAt: Date, source: BlockSource) {
        self.id = id
        self.activityId = activityId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
    }

    public var interval: DateInterval { DateInterval(start: startedAt, end: endedAt) }
}

extension Customer: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Project: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Activity: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Block: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Date {
    var roundedToSecond: Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded())
    }
}
