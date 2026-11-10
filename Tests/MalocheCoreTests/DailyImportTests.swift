import Foundation
import Testing

@testable import MalocheCore

/// Synthetic Daily exports: activities and timesheet as JSON.
enum DailyFixture {
    static func activities(_ entries: [(name: String, archived: Bool, lastUsed: String)]) -> Data {
        let items = entries.map {
            #"{"name": "\#($0.name)", "group": null, "archived": \#($0.archived), "lastUsed": "\#($0.lastUsed)"}"#
        }
        return Data("[\(items.joined(separator: ", "))]".utf8)
    }

    /// One day per entry; `started` nil leaves out `info`.
    static func timesheet(_ days: [(date: String, started: String?, durations: [(String, Int)])]) -> Data {
        let items = days.map { day in
            let activities = day.durations.map { #"{"activity": "\#($0.0)", "group": null, "duration": \#($0.1)}"# }
            let info =
                day.started.map {
                    #", "info": {"started": "\#($0)", "ended": "\#($0)", "total": \#(day.durations.map(\.1).reduce(0, +))}"#
                } ?? ""
            return #"{"date": "\#(day.date)", "activities": [\#(activities.joined(separator: ", "))]\#(info)}"#
        }
        return Data("[\(items.joined(separator: ", "))]".utf8)
    }

    static func export(
        _ activities: [(name: String, archived: Bool, lastUsed: String)],
        _ days: [(date: String, started: String?, durations: [(String, Int)])] = []
    ) throws -> DailyExport {
        try DailyExport(activities: Self.activities(activities), timesheet: timesheet(days))
    }

    static func names(_ names: [String]) -> [(name: String, archived: Bool, lastUsed: String)] {
        names.map { ($0, false, "2026-11-06T17:00:00+01:00") }
    }
}

/// S13: reading the Daily export and previewing what the import adds.
@Suite struct DailyImportTests {
    private func preview(
        _ export: DailyExport, activities: [Activity] = [], customers: [Customer] = [], blocks: [Block] = []
    ) -> DailyImport {
        DailyImport(
            export: export, activities: activities, customers: customers, blocks: blocks, calendar: Fixture.berlin)
    }

    private func planned(_ preview: DailyImport) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: preview.plan.activities.map { ($0.name, $0.customer) })
    }

    /// Customer and name of each planned activity.
    private func placed(_ preview: DailyImport) -> Set<[String?]> {
        Set(preview.plan.activities.map { [$0.customer, $0.name] })
    }

    @Test func bothFilesAreReadWithTheirOffsets() throws {
        let activities = Data(
            """
            [{"name": "Writing", "group": "Work", "archived": true, "lastUsed": "2026-03-30T10:00:00.250+02:00"},
             {"name": "Reading", "group": null, "archived": false, "lastUsed": "2026-11-06T16:30:00Z"}]
            """.utf8)
        let timesheet = Data(
            """
            [{"date": "2026-11-06", "activities": [{"activity": "Writing", "group": null, "duration": 5400},
              {"activity": "Reading", "group": "Work", "duration": 1800.0}],
              "info": {"started": "2026-11-06T08:15:00+01:00", "ended": "2026-11-06T10:15:00+01:00", "total": 7200}},
             {"date": "2026-11-07", "activities": []}]
            """.utf8)
        let export = try DailyExport(activities: activities, timesheet: timesheet)

        #expect(export.activities.map(\.name) == ["Writing", "Reading"])
        #expect(export.activities.map(\.archived) == [true, false])
        #expect(abs(export.activities[0].lastUsed!.timeIntervalSince(Fixture.at("2026-03-30 10:00")) - 0.25) < 0.001)
        #expect(export.activities[1].lastUsed == Fixture.at("2026-11-06 17:30"))
        #expect(export.days.map(\.date) == ["2026-11-06", "2026-11-07"])
        #expect(export.days[0].activities.map(\.activity) == ["Writing", "Reading"])
        #expect(export.days[0].activities.map(\.duration) == [5400, 1800])
        #expect(export.days[0].info?.started == Fixture.at("2026-11-06 08:15"))
        #expect(export.days[1].info == nil)
    }

    @Test func anUnreadableFileIsNamed() {
        let valid = DailyFixture.activities([])
        #expect(throws: DailyExport.ReadError.unreadable(.activities)) {
            try DailyExport(activities: Data("{".utf8), timesheet: valid)
        }
        #expect(throws: DailyExport.ReadError.unreadable(.timesheet)) {
            try DailyExport(activities: valid, timesheet: Data(#"{"date": "2026-11-06"}"#.utf8))
        }
        #expect(throws: DailyExport.ReadError.unreadable(.timesheet)) {
            try DailyExport(
                activities: valid,
                timesheet: Data(#"[{"date": "2026-11-06", "activities": [], "info": {"started": "today"}}]"#.utf8))
        }
    }

    @Test func theFilesAreFoundInTheFolderOrAsTheTwoChosenFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "maloche-daily-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let activities = folder.appending(path: "activities.json")
        let timesheet = folder.appending(path: "timesheet.json")
        try DailyFixture.activities(DailyFixture.names(["Writing"])).write(to: activities)
        try DailyFixture.timesheet([("2026-11-06", "2026-11-06T08:00:00+01:00", [("Writing", 60)])])
            .write(to: timesheet)

        #expect(try DailyExport(contentsOf: [folder]).activities.map(\.name) == ["Writing"])
        #expect(try DailyExport(contentsOf: [timesheet, activities]).days.count == 1)
        #expect(throws: DailyExport.ReadError.notFound) { try DailyExport(contentsOf: [activities]) }
        let empty = folder.appending(path: "empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: DailyExport.ReadError.notFound) { try DailyExport(contentsOf: [empty]) }
    }

    @Test func prefixesOfXDashYNamesAreFoundWithTheirCount() throws {
        let export = try DailyFixture.export(
            DailyFixture.names([
                "nordlicht - Code Review", "nordlicht - Abstimmung", "Writing", "hafenwerk - Weekly", "pf - Steuer",
                "a - ", "x-y",
            ]),
            [("2026-11-06", "2026-11-06T08:00:00+01:00", [("Nordlicht - Kickoff", 600)])])
        let preview = preview(export, customers: [Customer(id: 1, name: "PF", colorIndex: 0)])

        #expect(preview.activityCount == 8)
        #expect(preview.prefixes.map(\.text) == ["nordlicht", "hafenwerk", "pf"])
        #expect(preview.prefixes.map(\.count) == [3, 1, 1])
        #expect(preview.prefixes.map(\.customerName) == ["Nordlicht", "Hafenwerk", "PF"])
        #expect(preview.prefixes.map(\.isOn) == [true, false, true])
        #expect(preview.removesPrefix)
    }

    @Test func aCheckedPrefixAssignsTheCustomerAndAnUncheckedOneChangesNothing() throws {
        let export = try DailyFixture.export(
            DailyFixture.names(["nordlicht - Code Review", "Nordlicht - Kickoff", "hafenwerk - Weekly", "Writing"]))
        var preview = preview(export)
        preview.prefixes[0].customerName = " Nordlicht GmbH "
        preview.prefixes[1].isOn = false

        #expect(
            planned(preview) == [
                "Code Review": "Nordlicht GmbH", "Kickoff": "Nordlicht GmbH", "hafenwerk - Weekly": nil,
                "Writing": nil,
            ])
        preview.removesPrefix = false
        #expect(
            planned(preview) == [
                "nordlicht - Code Review": "Nordlicht GmbH", "Nordlicht - Kickoff": "Nordlicht GmbH",
                "hafenwerk - Weekly": nil, "Writing": nil,
            ])
        preview.prefixes[0].customerName = " "
        #expect(planned(preview)["nordlicht - Code Review"] == "nordlicht")
    }

    @Test func twoCustomersKeepTheSameShortNameAndTheirBlocksFollow() throws {
        let export = try DailyFixture.export(
            DailyFixture.names(["nordlicht - Meeting", "hafenwerk - meeting", "Meeting", "nordlicht - Writing"]),
            [
                (
                    "2026-11-06", "2026-11-06T08:00:00+01:00",
                    [("nordlicht - Meeting", 600), ("hafenwerk - meeting", 300), ("Meeting", 60)]
                )
            ])
        var preview = preview(
            export, activities: [Activity(id: 1, name: "Writing"), Activity(id: 2, name: "MEETING", customerId: 20)],
            customers: [Customer(id: 20, name: "Nordlicht", colorIndex: 0)])
        for index in preview.prefixes.indices { preview.prefixes[index].isOn = true }

        #expect(
            placed(preview) == [
                ["Nordlicht", "Meeting"], ["Hafenwerk", "meeting"], [nil, "Meeting"], ["Nordlicht", "Writing"],
            ])
        #expect(preview.keepingFullName.isEmpty)
        #expect(
            preview.plan.days[0].blocks.map { [$0.customer, $0.activity] } == [
                ["Nordlicht", "Meeting"], ["Hafenwerk", "meeting"], [nil, "Meeting"],
            ])
    }

    @Test func shortNamesThatMeetWithinACustomerOrAreReservedKeepTheFullName() throws {
        let export = try DailyFixture.export(
            DailyFixture.names([
                "nordlicht - review", "nordlicht - Break", "nordlicht - Kickoff", "nl - Review", "Kickoff",
            ]))
        var preview = preview(
            export,
            activities: [
                Activity(id: 1, name: "kickoff", customerId: 20), Activity(id: 3, name: "Break", kind: .break),
            ],
            customers: [Customer(id: 20, name: "Nordlicht", colorIndex: 0)])
        preview.prefixes[1].isOn = true
        preview.prefixes[1].customerName = "NORDLICHT"

        #expect(
            placed(preview) == [
                ["Nordlicht", "nordlicht - review"], ["Nordlicht", "nordlicht - Break"], ["Nordlicht", "Kickoff"],
                ["NORDLICHT", "nl - Review"], [nil, "Kickoff"],
            ])
        #expect(preview.keepingFullName == ["nl - Review", "nordlicht - Break", "nordlicht - review"])
        preview.removesPrefix = false
        #expect(preview.keepingFullName.isEmpty)
    }

    @Test func eachDayIsLaidOutFromItsStartInTheListedOrder() throws {
        let export = try DailyFixture.export(
            [("Writing", true, "2026-11-01T09:00:00+01:00"), ("Reading", false, "2026-11-09T09:00:00+01:00")],
            [
                ("2026-11-06", "2026-11-06T08:15:00+01:00", [("Writing", 5400), ("Reading", 1800), ("Writing", 0)]),
                ("2026-11-07", "2026-11-07T09:00:30.400+01:00", [("Reading", 3600), ("Meeting", 900)]),
                ("2026-11-08", nil, [("Writing", 600)]),
            ])
        let preview = preview(export)

        #expect(preview.dayCount == 3)
        #expect(preview.firstDay == Fixture.at("2026-11-06 00:00"))
        #expect(preview.lastDay == Fixture.at("2026-11-08 00:00"))
        #expect(preview.skippedDays == 1)
        #expect(preview.daysWithTime == 0)
        let days = preview.plan.days
        #expect(
            days.map(\.interval) == [
                Fixture.span("2026-11-06 00:00", "2026-11-07 00:00"),
                Fixture.span("2026-11-07 00:00", "2026-11-08 00:00"),
            ])
        #expect(
            days[0].blocks == [
                .init(activity: "Writing", start: Fixture.at("2026-11-06 08:15"), end: Fixture.at("2026-11-06 09:45")),
                .init(activity: "Reading", start: Fixture.at("2026-11-06 09:45"), end: Fixture.at("2026-11-06 10:15")),
            ])
        #expect(
            days[1].blocks == [
                .init(
                    activity: "Reading", start: Fixture.at("2026-11-07 09:00:30"),
                    end: Fixture.at("2026-11-07 10:00:30")),
                .init(
                    activity: "Meeting", start: Fixture.at("2026-11-07 10:00:30"),
                    end: Fixture.at("2026-11-07 10:15:30")),
            ])
        let activities = Dictionary(uniqueKeysWithValues: preview.plan.activities.map { ($0.name, $0) })
        #expect(preview.activityCount == 3)
        #expect(activities["Writing"]?.archived == true)
        #expect(activities["Writing"]?.lastUsedAt == Fixture.at("2026-11-06 09:45"))
        #expect(activities["Reading"]?.lastUsedAt == Fixture.at("2026-11-09 09:00"))
        #expect(activities["Meeting"]?.archived == false)
        #expect(activities["Meeting"]?.lastUsedAt == Fixture.at("2026-11-07 10:15:30"))
    }

    @Test func aDSTDayKeepsItsTotalAndADayLongerThanItsHoursIsSkipped() throws {
        let export = try DailyFixture.export(
            DailyFixture.names(["Writing"]),
            [
                ("2026-03-29", "2026-03-29T01:00:00+01:00", [("Writing", 3600), ("Writing", 3600)]),
                ("2026-03-30", "2026-03-30T08:00:00+02:00", [("Writing", 25 * 3600)]),
            ])
        let preview = preview(export)

        #expect(preview.skippedDays == 1)
        #expect(preview.plan.days.map(\.interval.duration) == [23 * 3600])
        #expect(
            preview.plan.days[0].blocks.map(\.start) == [
                Fixture.at("2026-03-29 01:00"), Fixture.at("2026-03-29 03:00"),
            ])
        #expect(preview.plan.days[0].blocks.map { $0.end.timeIntervalSince($0.start) } == [3600, 3600])

        let spring = try DailyFixture.export(
            DailyFixture.names(["Writing"]),
            [("2026-03-29", "2026-03-29T01:00:00+01:00", [("Writing", 23 * 3600 + 1)])])
        #expect(self.preview(spring).skippedDays == 1)
    }

    @Test func aDayRunningPastMidnightEndsAtMidnightAndAStartBeforeTheDayMovesIntoIt() throws {
        let export = try DailyFixture.export(
            DailyFixture.names(["Writing"]),
            [
                ("2026-11-06", "2026-11-06T22:00:00+01:00", [("Writing", 3 * 3600)]),
                ("2026-11-07", "2026-11-06T23:30:00+01:00", [("Writing", 3600)]),
                ("2026-11-07", "2026-11-07T08:00:00+01:00", [("Writing", 3600)]),
            ])
        let preview = preview(export)

        #expect(
            preview.plan.days.map(\.blocks.first?.start) == [
                Fixture.at("2026-11-06 21:00"), Fixture.at("2026-11-07 00:00"),
            ])
        #expect(
            preview.plan.days.map(\.blocks.last?.end) == [
                Fixture.at("2026-11-07 00:00"), Fixture.at("2026-11-07 01:00"),
            ])
        #expect(preview.skippedDays == 1, "the second 2026-11-07")
    }

    @Test func daysWithTimeInMalocheAreLeftAsTheyAre() throws {
        let export = try DailyFixture.export(
            DailyFixture.names(["Writing"]),
            [
                ("2026-11-05", "2026-11-05T08:00:00+01:00", [("Writing", 600)]),
                ("2026-11-06", "2026-11-06T08:00:00+01:00", [("Writing", 600)]),
            ])
        let late = Block(
            id: 1, activityId: 1, startedAt: Fixture.at("2026-11-04 23:00"), endedAt: Fixture.at("2026-11-05 00:30"),
            source: .checkIn)
        let preview = preview(export, activities: [Activity(id: 1, name: "Writing")], blocks: [late])

        #expect(preview.dayCount == 2)
        #expect(preview.daysWithTime == 1)
        #expect(preview.plan.days.map(\.interval.start) == [Fixture.at("2026-11-06 00:00")])
    }
}
