import Foundation
import Testing

@testable import WamaduCore

/// S13: writing a Daily import into the database in one transaction.
@Suite struct DailyImportStoreTests {
    private let database: AppDatabase
    private let export: DailyExport

    init() throws {
        database = try AppDatabase.inMemory()
        export = try DailyFixture.export(
            [
                ("nordlicht - Code Review", false, "2026-11-06T17:00:00+01:00"),
                ("nordlicht - Abstimmung", true, "2026-10-01T09:00:00+02:00"),
                ("Writing", false, "2026-11-01T09:00:00+01:00"),
                ("break", false, "2026-11-06T12:30:00+01:00"),
            ],
            [
                (
                    "2026-11-05", "2026-11-05T08:00:00+01:00",
                    [("nordlicht - Code Review", 3600), ("break", 1800), ("Writing", 900)]
                ),
                ("2026-11-06", "2026-11-06T09:00:00+01:00", [("Writing", 1800), ("nordlicht - Code Review", 600)]),
            ])
    }

    private func importAll(_ edit: (inout DailyImport) -> Void = { _ in }) throws {
        var preview = try database.dailyImport(export, calendar: Fixture.berlin)
        edit(&preview)
        try database.importDaily(preview.plan)
    }

    private func activity(_ name: String) throws -> Activity? {
        try database.activities().first { $0.name == name }
    }

    private var everything: [Block] {
        get throws { try database.blocks(in: Fixture.span("2026-11-01 00:00", "2026-11-10 00:00")) }
    }

    @Test func blocksAreWrittenPerDayAsImportedWithTheChosenCustomers() throws {
        try importAll()

        let customer = try #require(try database.customers().first)
        #expect(try database.customers().map(\.name) == ["Nordlicht"])
        let review = try #require(try activity("Code Review"))
        let abstimmung = try #require(try activity("Abstimmung"))
        let writing = try #require(try activity("Writing"))
        let breakId = try database.builtIn(.break).id!
        #expect([review.customerId, abstimmung.customerId, writing.customerId] == [customer.id, customer.id, nil])
        #expect(review.projectId == nil)
        #expect(abstimmung.archived && !review.archived)
        #expect(abstimmung.lastUsedAt == Fixture.at("2026-10-01 09:00"))
        #expect(review.lastUsedAt == Fixture.at("2026-11-06 17:00"))
        #expect(writing.lastUsedAt == Fixture.at("2026-11-06 09:30"))
        #expect(try database.activities().count { $0.name.caseInsensitiveCompare("break") == .orderedSame } == 1)

        let blocks = try everything
        #expect(blocks.allSatisfy { $0.source == .imported })
        #expect(blocks.map(\.activityId) == [review.id, breakId, writing.id, writing.id, review.id])
        #expect(
            blocks.map(\.startedAt) == [
                Fixture.at("2026-11-05 08:00"), Fixture.at("2026-11-05 09:00"), Fixture.at("2026-11-05 09:30"),
                Fixture.at("2026-11-06 09:00"), Fixture.at("2026-11-06 09:30"),
            ])
        #expect(blocks.map { $0.endedAt.timeIntervalSince($0.startedAt) } == [3600, 1800, 900, 1800, 600])
    }

    @Test func existingActivitiesAndCustomersAreReusedAndKeepTheirPlace() throws {
        let nordlicht = try database.createCustomer(name: "NORDLICHT")
        _ = try database.createActivity(name: "code review", customerId: nordlicht.id)
        let writing = try database.createActivity(name: "writing")
        try database.setArchived(true, activities: [writing.id!])
        try database.insert(
            block: Block(
                activityId: writing.id!, startedAt: Fixture.at("2026-11-08 09:00"),
                endedAt: Fixture.at("2026-11-08 10:00"), source: .checkIn))

        try importAll()

        #expect(try database.customers().map(\.id) == [nordlicht.id])
        let activities = try database.activities().filter { $0.kind == .regular }
        #expect(activities.map(\.name).sorted() == ["Abstimmung", "code review", "writing"])
        #expect(try activity("code review")?.customerId == nordlicht.id)
        #expect(try activity("writing")?.archived == true)
        #expect(try activity("writing")?.lastUsedAt == Fixture.at("2026-11-08 10:00"), "the later one stays")
        #expect(try activity("code review")?.lastUsedAt == Fixture.at("2026-11-06 17:00"))
        #expect(try everything.filter { $0.source == .imported }.count == 5)
    }

    @Test func eachNameIsMatchedUnderItsCustomerOrAtTheTopLevel() throws {
        let nordlicht = try database.createCustomer(name: "Nordlicht")
        let hafenwerk = try database.createCustomer(name: "Hafenwerk")
        let shop = try database.createProject(name: "Shop", customerId: hafenwerk.id)
        let nordlichtMeeting = try database.createActivity(name: "meeting", customerId: nordlicht.id).id!
        let shopMeeting = try database.createActivity(name: "Meeting", projectId: shop.id).id!
        let export = try DailyFixture.export(
            DailyFixture.names(["nordlicht - Meeting", "hafenwerk - Meeting", "Meeting"]),
            [
                (
                    "2026-11-06", "2026-11-06T08:00:00+01:00",
                    [("nordlicht - Meeting", 600), ("hafenwerk - Meeting", 300), ("Meeting", 60)]
                )
            ])
        var preview = try database.dailyImport(export, calendar: Fixture.berlin)
        for index in preview.prefixes.indices { preview.prefixes[index].isOn = true }

        try database.importDaily(preview.plan)

        let meetings = try database.activities().filter { $0.name.caseInsensitiveCompare("meeting") == .orderedSame }
        #expect(meetings.count == 4)
        let hafenwerkMeeting = try #require(meetings.first { $0.customerId == hafenwerk.id })
        let topMeeting = try #require(meetings.first { $0.customerId == nil && $0.projectId == nil })
        #expect(hafenwerkMeeting.projectId == nil)
        #expect(
            try everything.map(\.activityId) == [nordlichtMeeting, hafenwerkMeeting.id!, topMeeting.id!])
        #expect(try database.blocks(ofActivities: [shopMeeting]).isEmpty)
    }

    @Test func uncheckedPrefixesKeepTheNameWithoutACustomer() throws {
        try importAll { $0.prefixes[0].isOn = false }
        #expect(try database.customers().isEmpty)
        #expect(try activity("nordlicht - Code Review")?.customerId == nil)
    }

    @Test func daysWithTimeStayUntouchedAndASecondImportAddsNothing() throws {
        let writing = try database.createActivity(name: "Writing")
        let existing = try #require(
            try database.insert(
                block: Block(
                    activityId: writing.id!, startedAt: Fixture.at("2026-11-06 14:00"),
                    endedAt: Fixture.at("2026-11-06 15:00"), source: .checkIn)))

        let preview = try database.dailyImport(export, calendar: Fixture.berlin)
        #expect(preview.daysWithTime == 1)
        try database.importDaily(preview.plan)
        let first = try everything
        #expect(first.filter { $0.startedAt >= Fixture.at("2026-11-06 00:00") } == [existing])
        #expect(first.count == 4)
        let counts = [try database.activities().count, try database.customers().count]

        let again = try database.dailyImport(export, calendar: Fixture.berlin)
        #expect(again.daysWithTime == 2)
        #expect(again.keepingFullName.isEmpty)
        try database.importDaily(again.plan)
        #expect(try everything == first)
        #expect([try database.activities().count, try database.customers().count] == counts)
    }

    @Test func aDayThatGotTimeAfterThePreviewIsSkipped() throws {
        let preview = try database.dailyImport(export, calendar: Fixture.berlin)
        let writing = try database.createActivity(name: "Writing")
        let tracked = try #require(
            try database.insert(
                block: Block(
                    activityId: writing.id!, startedAt: Fixture.at("2026-11-06 09:10"),
                    endedAt: Fixture.at("2026-11-06 09:20"), source: .checkIn)))

        try database.importDaily(preview.plan)
        #expect(try everything.filter { $0.startedAt >= Fixture.at("2026-11-06 00:00") } == [tracked])
    }

    @Test func aFailingImportWritesNothing() throws {
        var plan = try database.dailyImport(export, calendar: Fixture.berlin).plan
        plan.days[1].blocks.append(
            .init(activity: "Unknown", start: Fixture.at("2026-11-06 12:00"), end: Fixture.at("2026-11-06 13:00")))

        #expect(throws: WamaduError.activityNotFound) { try database.importDaily(plan) }
        #expect(try database.customers().isEmpty)
        #expect(try database.activities().count == 2)
        #expect(try everything.isEmpty)
    }

    @Test func unreadableFilesLeaveTheDatabaseUntouched() throws {
        try importAll()
        let before = (try database.activities(), try everything)
        #expect(throws: DailyExport.ReadError.unreadable(.timesheet)) {
            let export = try DailyExport(activities: DailyFixture.activities([]), timesheet: Data("[{".utf8))
            try database.importDaily(database.dailyImport(export, calendar: Fixture.berlin).plan)
        }
        #expect(try database.activities() == before.0)
        #expect(try everything == before.1)
    }
}
