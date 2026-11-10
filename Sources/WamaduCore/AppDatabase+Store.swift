import Foundation
import GRDB

public enum WamaduError: Error, Equatable {
    case emptyName
    case projectAndCustomer
    case activityNotFound
    case activityHasBlocks
    case builtInActivity
    case blockNotFound
}

extension AppDatabase {
    public func createCustomer(name: String) throws -> Customer {
        let name = try Self.validName(name)
        return try dbQueue.write { db in
            let used = try Int.fetchAll(db, sql: "SELECT colorIndex FROM customer")
            var customer = Customer(name: name, colorIndex: CustomerColor.nextIndex(used: used))
            try customer.insert(db)
            return customer
        }
    }

    public func createProject(name: String, customerId: Int64?) throws -> Project {
        var project = Project(name: try Self.validName(name), customerId: customerId)
        try dbQueue.write { db in try project.insert(db) }
        return project
    }

    public func createActivity(name: String, projectId: Int64? = nil, customerId: Int64? = nil) throws -> Activity {
        guard projectId == nil || customerId == nil else { throw WamaduError.projectAndCustomer }
        var activity = Activity(name: try Self.validName(name), projectId: projectId, customerId: customerId)
        try dbQueue.write { db in try activity.insert(db) }
        return activity
    }

    public func activities() throws -> [Activity] {
        try dbQueue.read { db in try Activity.fetchAll(db) }
    }

    public func projects() throws -> [Project] {
        try dbQueue.read { db in try Project.order(Column("name").collating(.nocase)).fetchAll(db) }
    }

    public func customers() throws -> [Customer] {
        try dbQueue.read { db in try Customer.order(Column("name").collating(.nocase)).fetchAll(db) }
    }

    public func builtIn(_ kind: ActivityKind) throws -> Activity {
        let activity = try dbQueue.read { db in try Activity.filter(Column("kind") == kind.rawValue).fetchOne(db) }
        guard let activity else { throw WamaduError.activityNotFound }
        return activity
    }

    public func renameActivity(id: Int64, to name: String) throws {
        let name = try Self.validName(name)
        try dbQueue.write { db in
            var activity = try Self.regularActivity(db, id: id)
            activity.name = name
            try activity.update(db)
        }
    }

    public func deleteActivity(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Self.regularActivity(db, id: id)
            guard try Block.filter(Column("activityId") == id).isEmpty(db) else {
                throw WamaduError.activityHasBlocks
            }
            _ = try Activity.deleteOne(db, id: id)
        }
    }

    /// Inserts the block and shortens, splits or deletes the stored blocks it overlaps.
    /// Times are rounded to whole seconds; a block that becomes empty is skipped and nil is returned.
    @discardableResult
    public func insert(block: Block) throws -> Block? {
        let block = Self.wholeSeconds(block)
        guard block.endedAt != block.startedAt else { return nil }
        return try dbQueue.write { db in try Self.insert(block, db) }
    }

    /// Replaces the blocks with one block of their activity and the source of the earliest over the interval,
    /// which wins over the other blocks it overlaps like `insert(block:)`.
    @discardableResult
    public func replaceBlocks(_ ids: [Int64], over interval: DateInterval) throws -> Block {
        try dbQueue.write { db in
            guard let first = try Block.filter(ids: ids).order(Column("startedAt")).fetchOne(db) else {
                throw WamaduError.blockNotFound
            }
            _ = try Block.deleteAll(db, ids: ids)
            let block = Block(
                activityId: first.activityId, startedAt: interval.start, endedAt: interval.end, source: first.source)
            return try Self.insert(Self.wholeSeconds(block), db)
        }
    }

    /// Books the blocks to another activity, their times stay.
    public func moveBlocks(_ ids: [Int64], to activityId: Int64) throws {
        try dbQueue.write { db in
            _ = try Block.filter(ids: ids).updateAll(db, Column("activityId").set(to: activityId))
            if let end = try Block.filter(ids: ids).fetchAll(db).map(\.endedAt).max() {
                try Self.markUsed(activityId, at: end, db)
            }
        }
    }

    public func deleteBlocks(_ ids: [Int64]) throws {
        _ = try dbQueue.write { db in try Block.deleteAll(db, ids: ids) }
    }

    /// Blocks overlapping the interval, sorted by start.
    public func blocks(in interval: DateInterval) throws -> [Block] {
        try dbQueue.read { db in
            try Self.overlapping(interval.start, interval.end).order(Column("startedAt")).fetchAll(db)
        }
    }

    private static func overlapping(_ start: Date, _ end: Date) -> QueryInterfaceRequest<Block> {
        Block.filter(Column("startedAt") < end && Column("endedAt") > start)
    }

    /// Inside a write, the block wins over the stored blocks it overlaps.
    private static func insert(_ block: Block, _ db: Database) throws -> Block {
        let overlapping = try overlapping(block.startedAt, block.endedAt).fetchAll(db)
        let changes = Timeline.changes(inserting: block, into: overlapping)
        _ = try Block.deleteAll(db, ids: changes.deletedIds)
        for updated in changes.updated { try updated.update(db) }
        var inserted = changes.inserted
        for index in inserted.indices { try inserted[index].insert(db) }
        try markUsed(block.activityId, at: block.endedAt, db)
        return inserted[0]
    }

    private static func markUsed(_ activityId: Int64, at date: Date, _ db: Database) throws {
        try db.execute(
            sql: "UPDATE activity SET lastUsedAt = ? WHERE id = ? AND (lastUsedAt IS NULL OR lastUsedAt < ?)",
            arguments: [date, activityId, date])
    }

    // stored dates keep milliseconds, sub-second fragments could round to empty blocks
    private static func wholeSeconds(_ block: Block) -> Block {
        var block = block
        block.startedAt = Date(timeIntervalSinceReferenceDate: block.startedAt.timeIntervalSinceReferenceDate.rounded())
        block.endedAt = Date(timeIntervalSinceReferenceDate: block.endedAt.timeIntervalSinceReferenceDate.rounded())
        return block
    }

    private static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WamaduError.emptyName }
        return trimmed
    }

    private static func regularActivity(_ db: Database, id: Int64) throws -> Activity {
        guard let activity = try Activity.fetchOne(db, id: id) else { throw WamaduError.activityNotFound }
        guard activity.kind == .regular else { throw WamaduError.builtInActivity }
        return activity
    }
}
