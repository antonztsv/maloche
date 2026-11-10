import Foundation
import GRDB
import Testing

@testable import MalocheCore

@Suite struct ModelStoreTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ minutes: Double) -> Date {
        base.addingTimeInterval(minutes * 60)
    }

    private func block(_ activity: Int64, _ from: Double, _ to: Double, source: BlockSource = .checkIn) -> Block {
        Block(id: nil, activityId: activity, startedAt: at(from), endedAt: at(to), source: source)
    }

    private func allBlocks(_ database: AppDatabase) throws -> [Block] {
        try database.dbQueue.read { db in try Block.order(Column("startedAt")).fetchAll(db) }
    }

    private func expectNoOverlaps(_ blocks: [Block]) {
        for (index, first) in blocks.enumerated() {
            for second in blocks[(index + 1)...] {
                #expect(
                    !(first.startedAt < second.endedAt && second.startedAt < first.endedAt),
                    "\(first) overlaps \(second)")
            }
        }
    }

    @Test func createsCustomersProjectsAndActivities() throws {
        let database = try AppDatabase.inMemory()
        let acme = try database.createCustomer(name: " Acme ")
        let globex = try database.createCustomer(name: "Globex")
        let website = try database.createProject(name: "Website", customerId: acme.id)
        let inHouse = try database.createProject(name: "Internal", customerId: nil)
        let writing = try database.createActivity(name: "Writing", projectId: website.id)
        let review = try database.createActivity(name: "Code Review", customerId: globex.id)
        let reading = try database.createActivity(name: "Reading")

        #expect(acme.name == "Acme")
        #expect(acme.colorIndex == 0)
        #expect(globex.colorIndex == 1)
        #expect(website.customerId == acme.id)
        #expect(inHouse.customerId == nil)
        #expect(writing.projectId == website.id && writing.customerId == nil)
        #expect(review.customerId == globex.id && review.projectId == nil)

        let activities = try database.activities()
        for created in [writing, review, reading] {
            let stored = try #require(activities.first { $0.id == created.id })
            #expect(stored == created)
            #expect(stored.kind == .regular)
            #expect(!stored.archived)
            #expect(stored.lastUsedAt == nil)
        }
    }

    @Test func customerNameIsUniqueIgnoringCase() throws {
        let database = try AppDatabase.inMemory()
        _ = try database.createCustomer(name: "Acme")
        #expect(throws: MalocheError.duplicateName) { try database.createCustomer(name: "ACME") }
        try database.dbQueue.write { db in
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "INSERT INTO customer (name, colorIndex) VALUES ('ACME', 1)")
            }
        }
    }

    @Test func emptyNamesAreRejected() throws {
        let database = try AppDatabase.inMemory()
        #expect(throws: MalocheError.emptyName) { try database.createActivity(name: "  ") }
        #expect(throws: MalocheError.emptyName) { try database.createCustomer(name: "") }
        #expect(throws: MalocheError.emptyName) { try database.createProject(name: "\n", customerId: nil) }
    }

    @Test func builtInActivitiesExistExactlyOnce() throws {
        let database = try AppDatabase.inMemory()
        let breakActivity = try database.builtIn(.break)
        let privateActivity = try database.builtIn(.private)
        #expect(breakActivity.name == "Break" && breakActivity.kind == .break)
        #expect(privateActivity.name == "Private" && privateActivity.kind == .private)

        let counts = try database.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT kind, COUNT(*) AS n FROM activity GROUP BY kind ORDER BY kind")
                .map { [$0["kind"] as String: $0["n"] as Int] }
        }
        #expect(counts == [["break": 1], ["private": 1]])

        try database.dbQueue.write { db in
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "INSERT INTO activity (name, kind) VALUES ('Coffee', 'break')")
            }
        }
    }

    @Test func activityCannotHaveBothProjectAndCustomer() throws {
        let database = try AppDatabase.inMemory()
        let acme = try database.createCustomer(name: "Acme")
        let website = try database.createProject(name: "Website", customerId: acme.id)

        #expect(throws: MalocheError.projectAndCustomer) {
            try database.createActivity(name: "Writing", projectId: website.id, customerId: acme.id)
        }
        try database.dbQueue.write { db in
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: "INSERT INTO activity (name, projectId, customerId) VALUES ('Writing', ?, ?)",
                    arguments: [website.id, acme.id])
            }
        }
    }

    @Test func insertingBlockShortensAndDeletesOverlappedBlocks() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let review = try #require(try database.createActivity(name: "Code Review").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        _ = try database.insert(block: block(writing, 0, 60))
        _ = try database.insert(block: block(review, 60, 120))
        _ = try database.insert(block: block(writing, 120, 180))

        let inserted = try database.insert(block: block(reading, 30, 150, source: .manual))

        #expect(inserted?.id != nil)
        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [writing, reading, writing])
        #expect(stored.map(\.startedAt) == [at(0), at(30), at(150)])
        #expect(stored.map(\.endedAt) == [at(30), at(150), at(180)])
        expectNoOverlaps(stored)
    }

    @Test func insertingBlockInsideAnotherSplitsIt() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let breakId = try #require(try database.builtIn(.break).id)
        _ = try database.insert(block: block(writing, 0, 180, source: .continued))

        _ = try database.insert(block: block(breakId, 60, 90))

        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [writing, breakId, writing])
        #expect(stored.map(\.startedAt) == [at(0), at(60), at(90)])
        #expect(stored.map(\.endedAt) == [at(60), at(90), at(180)])
        #expect(stored.map(\.source) == [.continued, .checkIn, .continued])
        expectNoOverlaps(stored)
    }

    @Test func blockTimesAreStoredAsWholeSeconds() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let stored = try database.insert(
            block: Block(
                activityId: writing, startedAt: base.addingTimeInterval(0.4), endedAt: base.addingTimeInterval(60.7),
                source: .checkIn))
        #expect(stored?.startedAt == base)
        #expect(stored?.endedAt == base.addingTimeInterval(61))
        #expect(try allBlocks(database).map(\.endedAt) == [base.addingTimeInterval(61)])
    }

    @Test func subMillisecondRemainderDoesNotFailTheInsert() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        _ = try database.insert(block: block(writing, 0, 2))
        _ = try database.insert(
            block: Block(
                activityId: reading, startedAt: at(1), endedAt: at(2).addingTimeInterval(-0.0003), source: .checkIn))
        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [writing, reading])
        #expect(stored.map(\.endedAt) == [at(1), at(2)])
    }

    @Test func blockShorterThanASecondAfterRoundingIsSkipped() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let stored = try database.insert(
            block: Block(
                activityId: writing, startedAt: base.addingTimeInterval(10.2), endedAt: base.addingTimeInterval(10.4),
                source: .checkIn))
        #expect(stored == nil)
        #expect(try allBlocks(database).isEmpty)
    }

    @Test func bookingMovesLastUseOfTheActivityForwardOnly() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        try database.insert(block: block(writing, 60, 120))
        try database.insert(block: block(writing, 0, 30))
        let activity = try database.activities().first { $0.id == writing }
        #expect(activity?.lastUsedAt == at(120))
    }

    @Test func invalidBlockLeavesStoredBlocksUntouched() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        _ = try database.insert(block: block(writing, 0, 60))

        #expect(throws: DatabaseError.self) { try database.insert(block: block(writing, 40, 20)) }

        let stored = try allBlocks(database)
        #expect(stored.map(\.startedAt) == [at(0)])
        #expect(stored.map(\.endedAt) == [at(60)])
    }

    @Test func databaseRejectsOverlapsThatBypassTheStore() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        _ = try database.insert(block: block(writing, 0, 60))
        _ = try database.insert(block: block(writing, 60, 120))
        let before = try allBlocks(database)

        #expect(throws: DatabaseError.self) {
            try database.dbQueue.write { db in
                var overlapping = block(writing, 30, 90)
                try overlapping.insert(db)
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.dbQueue.write { db in
                var stretched = before[0]
                stretched.endedAt = at(90)
                try stretched.update(db)
            }
        }

        #expect(try allBlocks(database) == before)
    }

    @Test func blocksInIntervalReturnsOverlappingBlocksSortedByStart() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        _ = try database.insert(block: block(writing, 240, 300))
        _ = try database.insert(block: block(writing, 60, 120))
        _ = try database.insert(block: block(writing, 0, 60))

        let found = try database.blocks(in: DateInterval(start: at(30), end: at(90)))
        #expect(found.map(\.startedAt) == [at(0), at(60)])
        #expect(try database.blocks(in: DateInterval(start: at(120), end: at(240))).isEmpty)
    }

    @Test func deletingActivityWithBlocksIsRejected() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        _ = try database.insert(block: block(writing, 0, 60))

        #expect(throws: MalocheError.activityHasBlocks) { try database.deleteActivity(id: writing) }
        #expect(try database.activities().contains { $0.id == writing })
    }

    @Test func deletingUnusedActivityRemovesIt() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)

        try database.deleteActivity(id: writing)

        #expect(try !database.activities().contains { $0.id == writing })
    }

    @Test func renamingActivityTrimsAndRejectsEmptyNames() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)

        try database.renameActivity(id: writing, to: " Drafting ")
        #expect(throws: MalocheError.emptyName) { try database.renameActivity(id: writing, to: " ") }

        #expect(try database.activities().first { $0.id == writing }?.name == "Drafting")
    }

    @Test func builtInActivitiesCannotBeDeletedOrRenamed() throws {
        let database = try AppDatabase.inMemory()
        for kind in [ActivityKind.break, .private] {
            let id = try #require(try database.builtIn(kind).id)
            #expect(throws: MalocheError.builtInActivity) { try database.deleteActivity(id: id) }
            #expect(throws: MalocheError.builtInActivity) { try database.renameActivity(id: id, to: "Lunch") }
            #expect(try database.builtIn(kind).id == id)
        }
        #expect(try database.builtIn(.break).name == "Break")
        #expect(try database.builtIn(.private).name == "Private")
    }

    @Test func unknownActivityIsReported() throws {
        let database = try AppDatabase.inMemory()
        #expect(throws: MalocheError.activityNotFound) { try database.deleteActivity(id: 999) }
        #expect(throws: MalocheError.activityNotFound) { try database.renameActivity(id: 999, to: "Writing") }
    }

    // MARK: Editing an entry

    private func insertedId(_ database: AppDatabase, _ block: Block) throws -> Int64 {
        try #require(try database.insert(block: block)?.id)
    }

    @Test func aShorterSpanLeavesTheRestUntrackedAndNeighboursUnchanged() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        let first = try insertedId(database, block(writing, 0, 60, source: .manual))
        let second = try insertedId(database, block(writing, 60, 135))
        _ = try database.insert(block: block(reading, 135, 180))

        let replaced = try database.replaceBlocks([first, second], over: DateInterval(start: at(0), end: at(120)))

        #expect(replaced.activityId == writing)
        #expect(replaced.source == .manual)
        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [writing, reading])
        #expect(stored.map(\.startedAt) == [at(0), at(135)])
        #expect(stored.map(\.endedAt) == [at(120), at(180)])
        #expect(stored[0].id == replaced.id)
    }

    @Test func aLongerSpanShortensOrRemovesTheBlocksItNowCovers() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        let review = try #require(try database.createActivity(name: "Code Review").id)
        let span = try insertedId(database, block(writing, 0, 60))
        _ = try database.insert(block: block(reading, 60, 90))
        _ = try database.insert(block: block(review, 90, 150))

        try database.replaceBlocks([span], over: DateInterval(start: at(0), end: at(120)))

        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [writing, review])
        #expect(stored.map(\.startedAt) == [at(0), at(120)])
        #expect(stored.map(\.endedAt) == [at(120), at(150)])
        expectNoOverlaps(stored)
    }

    @Test func aSpanMovedIntoAnotherBlockSplitsIt() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        let span = try insertedId(database, block(writing, 0, 30, source: .split))
        _ = try database.insert(block: block(reading, 60, 180, source: .continued))

        try database.replaceBlocks([span], over: DateInterval(start: at(90), end: at(120)))

        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [reading, writing, reading])
        #expect(stored.map(\.startedAt) == [at(60), at(90), at(120)])
        #expect(stored.map(\.endedAt) == [at(90), at(120), at(180)])
        #expect(stored.map(\.source) == [.continued, .split, .continued])
        expectNoOverlaps(stored)
    }

    @Test func aReplacedSpanIsStoredInWholeSecondsAndMovesLastUseForward() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let span = try insertedId(database, block(writing, 0, 60))

        let replaced = try database.replaceBlocks(
            [span], over: DateInterval(start: at(0).addingTimeInterval(0.4), end: at(90).addingTimeInterval(0.6)))

        #expect(replaced.startedAt == at(0))
        #expect(replaced.endedAt == at(90).addingTimeInterval(1))
        #expect(try allBlocks(database).map(\.endedAt) == [at(90).addingTimeInterval(1)])
        #expect(try database.activities().first { $0.id == writing }?.lastUsedAt == at(90).addingTimeInterval(1))
    }

    @Test func aReplacementThatRoundsToNothingChangesNothing() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        let span = try insertedId(database, block(writing, 0, 60))
        _ = try database.insert(block: block(reading, 60, 120))
        let before = try allBlocks(database)

        #expect(throws: DatabaseError.self) {
            try database.replaceBlocks(
                [span], over: DateInterval(start: at(90).addingTimeInterval(0.2), end: at(90).addingTimeInterval(0.4)))
        }
        #expect(throws: MalocheError.blockNotFound) {
            try database.replaceBlocks([999], over: DateInterval(start: at(0), end: at(60)))
        }

        #expect(try allBlocks(database) == before)
    }

    @Test func movingBlocksBooksThemToTheOtherActivity() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        let breakId = try #require(try database.builtIn(.break).id)
        let first = try insertedId(database, block(writing, 0, 60))
        _ = try database.insert(block: block(reading, 60, 90))
        let second = try insertedId(database, block(writing, 90, 120))

        try database.moveBlocks([first, second], to: breakId)

        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [breakId, reading, breakId])
        #expect(stored.map(\.startedAt) == [at(0), at(60), at(90)])
        #expect(stored.map(\.endedAt) == [at(60), at(90), at(120)])
        #expect(try database.builtIn(.break).lastUsedAt == at(120))
        #expect(throws: DatabaseError.self) { try database.moveBlocks([first], to: 999) }
        #expect(try allBlocks(database) == stored)
    }

    @Test func deletingBlocksRemovesOnlyThose() throws {
        let database = try AppDatabase.inMemory()
        let writing = try #require(try database.createActivity(name: "Writing").id)
        let reading = try #require(try database.createActivity(name: "Reading").id)
        let first = try insertedId(database, block(writing, 0, 60))
        _ = try database.insert(block: block(reading, 60, 90))
        let second = try insertedId(database, block(writing, 90, 120))

        try database.deleteBlocks([first, second])

        let stored = try allBlocks(database)
        #expect(stored.map(\.activityId) == [reading])
        #expect(stored.map(\.startedAt) == [at(60)])
    }
}
