import Foundation
import GRDB

public enum MalocheError: Error, Equatable {
    case emptyName
    case projectAndCustomer
    case activityNotFound
    case builtInActivity
    case blockNotFound
    case duplicateName
    case notABackup
    case runningEntry
}

extension AppDatabase {
    public func createCustomer(name: String) throws -> Customer {
        let name = try Self.validName(name)
        return try dbQueue.write { db in
            try Self.checkUnique(name, among: Customer.fetchAll(db).map(\.name))
            let used = try Int.fetchAll(db, sql: "SELECT colorIndex FROM customer")
            var customer = Customer(name: name, colorIndex: CustomerColor.nextIndex(used: used))
            try customer.insert(db)
            return customer
        }
    }

    /// Project names are unique per customer ignoring case, those without customer among themselves.
    public func createProject(name: String, customerId: Int64?) throws -> Project {
        var project = Project(name: try Self.validName(name), customerId: customerId)
        try dbQueue.write { db in
            try Self.checkUnique(project, db)
            try project.insert(db)
        }
        return project
    }

    public func createActivity(name: String, projectId: Int64? = nil, customerId: Int64? = nil) throws -> Activity {
        guard projectId == nil || customerId == nil else { throw MalocheError.projectAndCustomer }
        var activity = Activity(name: try Self.validName(name), projectId: projectId, customerId: customerId)
        try dbQueue.write { db in
            try checkUnique(activity, db)
            try activity.insert(db)
        }
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
        guard let activity else { throw MalocheError.activityNotFound }
        return activity
    }

    public func renameActivity(id: Int64, to name: String) throws {
        let name = try Self.validName(name)
        try dbQueue.write { db in
            var activity = try Self.regularActivity(db, id: id)
            activity.name = name
            try checkUnique(activity, db)
            try activity.update(db)
        }
    }

    public func renameProject(id: Int64, to name: String) throws {
        let name = try Self.validName(name)
        try dbQueue.write { db in
            guard var project = try Project.fetchOne(db, id: id) else { return }
            project.name = name
            try Self.checkUnique(project, db)
            try project.update(db)
        }
    }

    public func renameCustomer(id: Int64, to name: String) throws {
        let name = try Self.validName(name)
        _ = try dbQueue.write { db in
            try Self.checkUnique(name, among: Customer.filter(Column("id") != id).fetchAll(db).map(\.name))
            return try Customer.filter(id: id).updateAll(db, Column("name").set(to: name))
        }
    }

    public func setColor(_ color: CustomerColor, ofCustomer id: Int64) throws {
        _ = try dbQueue.write { db in
            try Customer.filter(id: id).updateAll(db, Column("colorIndex").set(to: color.rawValue))
        }
    }

    /// Archived activities leave the check-in suggestions, their time stays in every report.
    public func setArchived(_ archived: Bool, activities ids: [Int64]) throws {
        try dbQueue.write { db in
            for id in ids { _ = try Self.regularActivity(db, id: id) }
            _ = try Activity.filter(ids: ids).updateAll(db, Column("archived").set(to: archived))
        }
    }

    /// The project, the customer directly or neither; it applies to all time of the activities, past included.
    public func moveActivities(_ ids: [Int64], projectId: Int64?, customerId: Int64?) throws {
        guard projectId == nil || customerId == nil else { throw MalocheError.projectAndCustomer }
        try dbQueue.write { db in
            for id in ids {
                var activity = try Self.regularActivity(db, id: id)
                (activity.projectId, activity.customerId) = (projectId, customerId)
                try checkUnique(activity, db)
                try activity.update(db)
            }
        }
    }

    /// Books every block of the activities to the target, their times stay, then deletes them; returns the moved
    /// block count.
    @discardableResult
    public func mergeActivities(_ ids: [Int64], into target: Int64) throws -> Int {
        let ids = ids.filter { $0 != target }
        return try dbQueue.write { db in
            _ = try Self.regularActivity(db, id: target)
            for id in ids { _ = try Self.regularActivity(db, id: id) }
            let blocks = Block.filter(ids.contains(Column("activityId")))
            let end = try blocks.fetchAll(db).map(\.endedAt).max()
            let moved = try blocks.updateAll(db, Column("activityId").set(to: target))
            _ = try Activity.deleteAll(db, ids: ids)
            if let end { try Self.markUsed(target, at: end, db) }
            return moved
        }
    }

    /// Deletes the activities with all their blocks; Break and Private stay.
    public func deleteActivities(_ ids: [Int64]) throws {
        try dbQueue.write { db in
            for id in ids { _ = try Self.regularActivity(db, id: id) }
            _ = try Block.filter(ids.contains(Column("activityId"))).deleteAll(db)
            _ = try Activity.deleteAll(db, ids: ids)
        }
    }

    /// Deletes exactly the span of a drawn entry from the activity's blocks, parts outside it stay as shorter blocks.
    public func deleteEntry(activityId: Int64, in interval: DateInterval) throws {
        try dbQueue.write { db in
            let blocks = try Self.overlapping(interval.start, interval.end)
                .filter(Column("activityId") == activityId).fetchAll(db)
            guard !blocks.isEmpty else { throw MalocheError.blockNotFound }
            let span = Block(activityId: activityId, startedAt: interval.start, endedAt: interval.end, source: .manual)
            let changes = Timeline.changes(inserting: span, into: blocks)
            _ = try Block.deleteAll(db, ids: changes.deletedIds)
            for updated in changes.updated { try updated.update(db) }
            // the first inserted block is the span itself
            for var tail in changes.inserted.dropFirst() { try tail.insert(db) }
        }
    }

    public func hasBlocks() throws -> Bool {
        try dbQueue.read { try !Block.all().isEmpty($0) }
    }

    /// Blocks of the activities, sorted by start.
    public func blocks(ofActivities ids: [Int64]) throws -> [Block] {
        try dbQueue.read { db in
            try Block.filter(ids.contains(Column("activityId"))).order(Column("startedAt")).fetchAll(db)
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

    /// Blocks overlapping the interval, sorted by start.
    public func blocks(in interval: DateInterval) throws -> [Block] {
        try dbQueue.read { db in
            try Self.overlapping(interval.start, interval.end).order(Column("startedAt")).fetchAll(db)
        }
    }

    /// The preview of importing the export into what maloche has.
    public func dailyImport(_ export: DailyExport, calendar: Calendar) throws -> DailyImport {
        try dbQueue.read { db in
            DailyImport(
                export: export, activities: try Activity.fetchAll(db), builtInNames: builtInNames,
                customers: try Customer.fetchAll(db), blocks: try Block.fetchAll(db), calendar: calendar)
        }
    }

    /// In one transaction: customers by name and activities by name directly under their customer or at the top level,
    /// ignoring case, Break and Private also under their shown names, and the blocks of each day that still has no
    /// time.
    public func importDaily(_ plan: DailyImport.Plan) throws {
        try dbQueue.write { db in
            var customers = try Customer.fetchAll(db)
            func customerId(_ name: String) throws -> Int64? {
                if let customer = customers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    return customer.id
                }
                var customer = Customer(
                    name: name, colorIndex: CustomerColor.nextIndex(used: customers.map(\.colorIndex)))
                try customer.insert(db)
                customers.append(customer)
                return customer.id
            }
            // Break and Private win over a regular activity named like their shown names
            let activities = try Activity.fetchAll(db).sorted { $0.kind != .regular && $1.kind == .regular }
            var ids: [[String?]: Int64] = [:]
            for planned in plan.activities {
                let owner = try planned.customer.flatMap(customerId)
                let key = [planned.customer?.lowercased(), planned.name.lowercased()]
                if let existing = activities.first(where: {
                    ($0.projectId, $0.customerId) == (nil, owner)
                        && ([$0.name] + [builtInNames[$0.kind]].compactMap { $0 }).contains {
                            $0.caseInsensitiveCompare(planned.name) == .orderedSame
                        }
                }), let id = existing.id {
                    if let date = planned.lastUsedAt { try Self.markUsed(id, at: date, db) }
                    ids[key] = id
                } else {
                    var activity = Activity(
                        name: planned.name, customerId: owner, archived: planned.archived,
                        lastUsedAt: planned.lastUsedAt)
                    try activity.insert(db)
                    ids[key] = activity.id
                }
            }
            for day in plan.days {
                guard try Self.overlapping(day.interval.start, day.interval.end).isEmpty(db) else { continue }
                for planned in day.blocks {
                    guard let id = ids[[planned.customer?.lowercased(), planned.activity.lowercased()]] else {
                        throw MalocheError.activityNotFound
                    }
                    var block = Block(activityId: id, startedAt: planned.start, endedAt: planned.end, source: .imported)
                    try block.insert(db)
                }
            }
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
        block.startedAt = block.startedAt.roundedToSecond
        block.endedAt = block.endedAt.roundedToSecond
        return block
    }

    private static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MalocheError.emptyName }
        return trimmed
    }

    /// Compared like the check-in matches names.
    private static func checkUnique(_ name: String, among names: [String]) throws {
        if names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            throw MalocheError.duplicateName
        }
    }

    /// Within its project, else its customer, else the top level; archived ones count, Break and Private under both
    /// names everywhere.
    private func checkUnique(_ activity: Activity, _ db: Database) throws {
        let others = try Activity.fetchAll(db).filter {
            $0.id != activity.id
                && ($0.kind != .regular || ($0.projectId, $0.customerId) == (activity.projectId, activity.customerId))
        }
        try Self.checkUnique(activity.name, among: others.map(\.name) + builtInNames.values)
    }

    private static func checkUnique(_ project: Project, _ db: Database) throws {
        let others = try Project.fetchAll(db).filter { $0.id != project.id && $0.customerId == project.customerId }
        try checkUnique(project.name, among: others.map(\.name))
    }

    private static func regularActivity(_ db: Database, id: Int64) throws -> Activity {
        guard let activity = try Activity.fetchOne(db, id: id) else { throw MalocheError.activityNotFound }
        guard activity.kind == .regular else { throw MalocheError.builtInActivity }
        return activity
    }
}
