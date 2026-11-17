import Foundation
import GRDB
import Testing

@testable import MalocheCore

/// Renaming, archiving, moving and merging in the Manage Activities window.
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

    @Test func activityNamesAreUniqueWithinTheirParentIgnoringCaseIncludingArchived() throws {
        try database.setArchived(true, activities: [writing, review])
        #expect(throws: MalocheError.duplicateName) { try database.createActivity(name: " WRITING ") }
        #expect(throws: MalocheError.duplicateName) {
            try database.createActivity(name: "code review", projectId: relaunch.id)
        }
        #expect(throws: MalocheError.duplicateName) {
            try database.createActivity(name: "weekly", customerId: northwind.id)
        }

        let elsewhere = [
            try database.createActivity(name: "Code Review", projectId: shop.id),
            try database.createActivity(name: "Weekly", customerId: acme.id),
            try database.createActivity(name: "Weekly"),
            try database.createActivity(name: "Writing", customerId: acme.id),
        ]
        #expect(elsewhere.map(\.name) == ["Code Review", "Weekly", "Weekly", "Writing"])
    }

    /// The names the app shows for Break and Private are reserved too, English keeps Pause and Privat free.
    @Test func theShownNamesOfBreakAndPrivateAreReservedUnderEveryParent() throws {
        let legacy = try database.createActivity(name: "Pause", customerId: northwind.id).id!
        var german = database
        german.builtInNames = [.break: "Pause", .private: "Privat"]
        #expect(throws: MalocheError.duplicateName) { try german.createActivity(name: "pause") }
        #expect(throws: MalocheError.duplicateName) { try german.createActivity(name: "PAUSE", projectId: shop.id) }
        #expect(throws: MalocheError.duplicateName) { try german.createActivity(name: "Privat", customerId: acme.id) }
        #expect(throws: MalocheError.duplicateName) { try german.createActivity(name: "break") }
        #expect(throws: MalocheError.duplicateName) { try german.renameActivity(id: review, to: " pause ") }
        #expect(throws: MalocheError.duplicateName) { try german.renameActivity(id: weekly, to: "PRIVAT") }
        #expect(throws: MalocheError.duplicateName) {
            try german.moveActivities([legacy], projectId: shop.id, customerId: nil)
        }
        #expect(try database.createActivity(name: "Privat", customerId: acme.id).name == "Privat")
    }

    @Test func breakAndPrivateAreReservedUnderEveryParent() throws {
        #expect(throws: MalocheError.duplicateName) { try database.createActivity(name: "break") }
        #expect(throws: MalocheError.duplicateName) { try database.createActivity(name: "Break", projectId: shop.id) }
        #expect(throws: MalocheError.duplicateName) {
            try database.createActivity(name: "PRIVATE", customerId: acme.id)
        }
        #expect(throws: MalocheError.duplicateName) { try database.renameActivity(id: review, to: "private") }
    }

    @Test func renamingChecksTheParentOfTheActivity() throws {
        let planning = try database.createActivity(name: "Planning", projectId: relaunch.id).id!
        #expect(throws: MalocheError.duplicateName) { try database.renameActivity(id: review, to: " planning ") }
        #expect(throws: MalocheError.emptyName) { try database.renameActivity(id: review, to: " ") }

        try database.renameActivity(id: writing, to: "planning")
        try database.renameActivity(id: weekly, to: "Code Review")
        try database.renameActivity(id: review, to: "code review")
        #expect(
            try [writing, weekly, review, planning].map { try activity($0)?.name } == [
                "planning", "Code Review", "code review", "Planning",
            ])
    }

    @Test func movingChecksTheTargetParentAndChangesNothingWhenRefused() throws {
        let relaunchWeekly = try database.createActivity(name: "WEEKLY", projectId: relaunch.id).id!
        #expect(throws: MalocheError.duplicateName) {
            try database.moveActivities([relaunchWeekly], projectId: nil, customerId: northwind.id)
        }
        #expect(throws: MalocheError.duplicateName) {
            try database.moveActivities([writing, weekly, relaunchWeekly], projectId: shop.id, customerId: nil)
        }
        #expect(try placement(writing) == [nil, nil])
        #expect(try placement(weekly) == [nil, northwind.id])
        #expect(try placement(relaunchWeekly) == [relaunch.id, nil])

        try database.moveActivities([weekly], projectId: nil, customerId: northwind.id)
        try database.moveActivities([relaunchWeekly, writing], projectId: shop.id, customerId: nil)
        #expect(try placement(relaunchWeekly) == [shop.id, nil])
    }

    @Test func projectNamesAreUniquePerCustomer() throws {
        #expect(throws: MalocheError.duplicateName) {
            try database.createProject(name: " relaunch ", customerId: acme.id)
        }
        let northwindRelaunch = try database.createProject(name: "Relaunch", customerId: northwind.id)
        let tools = try database.createProject(name: "Tools", customerId: nil)
        #expect(throws: MalocheError.duplicateName) { try database.createProject(name: "TOOLS", customerId: nil) }
        _ = try database.createProject(name: "Tools", customerId: acme.id)

        #expect(throws: MalocheError.duplicateName) { try database.renameProject(id: shop.id!, to: "relaunch") }
        #expect(throws: MalocheError.duplicateName) { try database.renameProject(id: relaunch.id!, to: "tools") }
        try database.renameProject(id: northwindRelaunch.id!, to: "RELAUNCH")
        try database.renameProject(id: tools.id!, to: "Shop")
        let names = Dictionary(uniqueKeysWithValues: try database.projects().map { ($0.id!, $0.name) })
        #expect([names[northwindRelaunch.id!], names[tools.id!]] == ["RELAUNCH", "Shop"])
    }

    @Test func projectsAndCustomersAreRenamedTrimmed() throws {
        try database.renameProject(id: relaunch.id!, to: " Relaunch 2027 ")
        try database.renameCustomer(id: acme.id!, to: "Acme Inc.")
        #expect(try database.projects().first { $0.id == relaunch.id }?.name == "Relaunch 2027")
        #expect(try database.customers().first { $0.id == acme.id }?.name == "Acme Inc.")

        #expect(throws: MalocheError.emptyName) { try database.renameProject(id: shop.id!, to: "") }
        #expect(throws: MalocheError.emptyName) { try database.renameCustomer(id: acme.id!, to: "\n") }
        #expect(throws: MalocheError.duplicateName) { try database.renameCustomer(id: acme.id!, to: "northwind") }
        #expect(throws: MalocheError.duplicateName) { try database.createCustomer(name: "NORTHWIND") }
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

        #expect(throws: MalocheError.projectAndCustomer) {
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

    @Test func deletingRemovesTheActivitiesWithTheirTimeAndLeavesTheRest() throws {
        try book(writing, "09:00", "10:00")
        try book(weekly, "10:00", "10:30")
        try book(review, "10:30", "11:00")
        try book(writing, "11:00", "12:00")

        try database.deleteActivities([writing, weekly])

        let blocks = try database.blocks(in: Fixture.span("00:00", "23:59"))
        #expect(blocks.map(\.activityId) == [review])
        #expect(blocks.map(\.startedAt) == [Fixture.at("10:30")])
        #expect(try database.activities().filter { $0.kind == .regular }.map(\.id) == [review])
        #expect(try database.projects().contains { $0.id == relaunch.id })
    }

    @Test func aFailedDeleteChangesNothing() throws {
        try book(writing, "09:00", "10:00")
        let breakId = try database.builtIn(.break).id!
        #expect(throws: MalocheError.builtInActivity) { try database.deleteActivities([writing, breakId]) }
        #expect(throws: MalocheError.activityNotFound) { try database.deleteActivities([writing, 999]) }
        #expect(try database.blocks(in: Fixture.span("00:00", "23:59")).map(\.activityId) == [writing])
        #expect(try activity(writing) != nil)
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
        #expect(throws: MalocheError.builtInActivity) {
            try database.mergeActivities([writing, breakId], into: review)
        }
        #expect(throws: MalocheError.activityNotFound) { try database.mergeActivities([writing], into: 999) }
        #expect(try database.blocks(in: Fixture.span("00:00", "23:59")).map(\.activityId) == [writing])
        #expect(try activity(writing) != nil)
    }

    @Test func breakAndPrivateCannotBeRenamedArchivedMovedOrMerged() throws {
        for kind in [ActivityKind.break, .private] {
            let id = try database.builtIn(kind).id!
            #expect(throws: MalocheError.builtInActivity) { try database.renameActivity(id: id, to: "Pause") }
            #expect(throws: MalocheError.builtInActivity) { try database.setArchived(true, activities: [writing, id]) }
            #expect(throws: MalocheError.builtInActivity) {
                try database.moveActivities([id], projectId: relaunch.id, customerId: nil)
            }
            #expect(throws: MalocheError.builtInActivity) { try database.mergeActivities([id], into: writing) }
            #expect(throws: MalocheError.builtInActivity) { try database.mergeActivities([writing], into: id) }
            #expect(throws: MalocheError.builtInActivity) { try database.deleteActivities([id]) }
        }
        #expect(try activity(writing)?.archived == false)
    }

    @Test func mergingIntoItselfLeavesTheTarget() throws {
        try book(writing, "09:00", "10:00")
        #expect(try database.mergeActivities([writing], into: writing) == 0)
        #expect(try activity(writing) != nil)
    }
}
