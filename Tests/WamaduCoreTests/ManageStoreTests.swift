import Foundation
import GRDB
import Testing

@testable import WamaduCore

/// S8: renaming, archiving, moving and merging in the Manage Activities window.
@Suite struct ManageStoreTests {
    private let database: AppDatabase
    private let acme: Customer
    private let northwind: Customer
    private let relaunch: Project
    private let shop: Project
    private let writing: Int64
    private let review: Int64
    private let weekly: Int64

    init() throws {
        database = try AppDatabase.inMemory()
        acme = try database.createCustomer(name: "Acme")
        northwind = try database.createCustomer(name: "Northwind")
        relaunch = try database.createProject(name: "Relaunch", customerId: acme.id)
        shop = try database.createProject(name: "Shop", customerId: northwind.id)
        writing = try database.createActivity(name: "Writing").id!
        review = try database.createActivity(name: "Code Review", projectId: relaunch.id).id!
        weekly = try database.createActivity(name: "Weekly", customerId: northwind.id).id!
    }

    private func activity(_ id: Int64) throws -> Activity? {
        try database.activities().first { $0.id == id }
    }

    /// Project and customer of the activity.
    private func placement(_ id: Int64) throws -> [Int64?] {
        try activity(id).map { [$0.projectId, $0.customerId] } ?? []
    }

    private func book(_ id: Int64, _ from: String, _ to: String) throws {
        try database.insert(
            block: Block(activityId: id, startedAt: Fixture.at(from), endedAt: Fixture.at(to), source: .checkIn))
    }

    @Test func activityNamesAreUniqueIgnoringCaseIncludingArchivedAndBuiltIns() throws {
        try database.setArchived(true, activities: [writing])
        #expect(throws: WamaduError.duplicateName) { try database.renameActivity(id: review, to: " writing ") }
        #expect(throws: WamaduError.duplicateName) { try database.renameActivity(id: review, to: "break") }
        #expect(throws: WamaduError.duplicateName) { try database.createActivity(name: "WEEKLY") }
        #expect(throws: WamaduError.emptyName) { try database.renameActivity(id: review, to: " ") }

        try database.renameActivity(id: review, to: "code review")
        #expect(try activity(review)?.name == "code review")
    }

    @Test func projectsAndCustomersAreRenamedTrimmed() throws {
        try database.renameProject(id: relaunch.id!, to: " Relaunch 2027 ")
        try database.renameCustomer(id: acme.id!, to: "Acme Inc.")
        #expect(try database.projects().first { $0.id == relaunch.id }?.name == "Relaunch 2027")
        #expect(try database.customers().first { $0.id == acme.id }?.name == "Acme Inc.")

        #expect(throws: WamaduError.emptyName) { try database.renameProject(id: shop.id!, to: "") }
        #expect(throws: WamaduError.emptyName) { try database.renameCustomer(id: acme.id!, to: "\n") }
        #expect(throws: WamaduError.duplicateName) { try database.renameCustomer(id: acme.id!, to: "northwind") }
        #expect(throws: WamaduError.duplicateName) { try database.createCustomer(name: "NORTHWIND") }
        try database.renameCustomer(id: acme.id!, to: "ACME INC.")
        #expect(try database.customers().first { $0.id == acme.id }?.name == "ACME INC.")
    }

    @Test func aCustomerTakesAnyColorOfThePalette() throws {
        try database.setColor(.brown, ofCustomer: acme.id!)
        #expect(try database.customers().first { $0.id == acme.id }?.colorIndex == CustomerColor.brown.rawValue)
        #expect(try database.customers().first { $0.id == northwind.id }?.colorIndex == CustomerColor.purple.rawValue)
    }

    @Test func archivingKeepsTheTimeAndUnarchivingBringsTheActivityBack() throws {
        try book(writing, "09:00", "10:00")
        try database.setArchived(true, activities: [writing, review])
        #expect(try activity(writing)?.archived == true)
        #expect(try activity(review)?.archived == true)
        #expect(try database.blocks(in: Fixture.span("00:00", "23:59")).map(\.activityId) == [writing])

        try database.setArchived(false, activities: [writing])
        #expect(try activity(writing)?.archived == false)
        #expect(try activity(review)?.archived == true)
    }

    @Test func movingToAProjectOrCustomerReplacesTheFormerOne() throws {
        try database.moveActivities([writing, weekly], projectId: shop.id, customerId: nil)
        #expect(try placement(writing) == [shop.id, nil])
        #expect(try placement(weekly) == [shop.id, nil])

        try database.moveActivities([review, weekly], projectId: nil, customerId: acme.id)
        #expect(try placement(review) == [nil, acme.id])
        #expect(try placement(weekly) == [nil, acme.id])

        try database.moveActivities([review], projectId: nil, customerId: nil)
        #expect(try placement(review) == [nil, nil])

        #expect(throws: WamaduError.projectAndCustomer) {
            try database.moveActivities([writing], projectId: shop.id, customerId: acme.id)
        }
    }

    @Test func mergingBooksEveryBlockToTheTargetAndRemovesTheMergedActivities() throws {
        try book(writing, "09:00", "10:00")
        try book(weekly, "10:00", "10:30")
        try book(review, "10:30", "11:00")
        try book(writing, "11:00", "12:00")

        let moved = try database.mergeActivities([writing, weekly], into: review)

        #expect(moved == 3)
        let blocks = try database.blocks(in: Fixture.span("00:00", "23:59"))
        #expect(blocks.map(\.activityId) == [review, review, review, review])
        #expect(blocks.map(\.startedAt) == ["09:00", "10:00", "10:30", "11:00"].map(Fixture.at))
        let remaining = try database.activities().filter { $0.kind == .regular }
        #expect(remaining.map(\.id) == [review])
        #expect(remaining.first?.lastUsedAt == Fixture.at("12:00"))
    }

    @Test func blocksOfActivitiesFeedTheMergeConfirmation() throws {
        try book(writing, "09:00", "10:00")
        try book(weekly, "10:00", "10:30")
        try book(review, "10:30", "11:00")
        let blocks = try database.blocks(ofActivities: [writing, weekly])
        #expect(blocks.map(\.activityId) == [writing, weekly])
    }

    @Test func aFailedMergeChangesNothing() throws {
        try book(writing, "09:00", "10:00")
        let breakId = try database.builtIn(.break).id!
        #expect(throws: WamaduError.builtInActivity) { try database.mergeActivities([writing, breakId], into: review) }
        #expect(throws: WamaduError.activityNotFound) { try database.mergeActivities([writing], into: 999) }
        #expect(try database.blocks(in: Fixture.span("00:00", "23:59")).map(\.activityId) == [writing])
        #expect(try activity(writing) != nil)
    }

    @Test func breakAndPrivateCannotBeRenamedArchivedMovedOrMerged() throws {
        for kind in [ActivityKind.break, .private] {
            let id = try database.builtIn(kind).id!
            #expect(throws: WamaduError.builtInActivity) { try database.renameActivity(id: id, to: "Pause") }
            #expect(throws: WamaduError.builtInActivity) { try database.setArchived(true, activities: [writing, id]) }
            #expect(throws: WamaduError.builtInActivity) {
                try database.moveActivities([id], projectId: relaunch.id, customerId: nil)
            }
            #expect(throws: WamaduError.builtInActivity) { try database.mergeActivities([id], into: writing) }
            #expect(throws: WamaduError.builtInActivity) { try database.mergeActivities([writing], into: id) }
        }
        #expect(try activity(writing)?.archived == false)
    }

    @Test func mergingIntoItselfLeavesTheTarget() throws {
        try book(writing, "09:00", "10:00")
        #expect(try database.mergeActivities([writing], into: writing) == 0)
        #expect(try activity(writing) != nil)
    }
}
