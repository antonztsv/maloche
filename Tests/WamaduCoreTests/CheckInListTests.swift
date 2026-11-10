import Foundation
import Testing

@testable import WamaduCore

@Suite struct CheckInListTests {
    private static func block(_ activity: Int64, _ start: String, _ end: String) -> Block {
        Block(activityId: activity, startedAt: Fixture.at(start), endedAt: Fixture.at(end), source: .checkIn)
    }

    private let catalog = Catalog(
        activities: [
            Activity(id: 1, name: "Code Review", projectId: 10, lastUsedAt: Fixture.at("10:15")),
            Activity(id: 2, name: "Writing", lastUsedAt: Fixture.at("09:00")),
            Activity(id: 3, name: "Weekly", customerId: 2, lastUsedAt: Fixture.at("09:30")),
            Activity(id: 4, name: "Planning", customerId: 2, lastUsedAt: Fixture.at("2026-11-06 12:00")),
            Activity(id: 5, name: "Old Stuff", archived: true, lastUsedAt: Fixture.at("2026-11-05 12:00")),
            Activity(id: 100, name: "Break", kind: .break),
            Activity(id: 101, name: "Private", kind: .private),
        ],
        projects: [Project(id: 10, name: "Relaunch", customerId: 1)],
        customers: [Customer(id: 1, name: "Acme", colorIndex: 0), Customer(id: 2, name: "Northwind", colorIndex: 1)],
        todayBlocks: [block(2, "08:30", "09:00"), block(3, "09:00", "09:30"), block(1, "09:30", "10:15")]
    )

    private func names(_ list: CheckInList) -> [String] {
        list.rows.map { row in
            switch row {
            case .create(let name): "+\(name)"
            case .activity(let suggestion, _): suggestion.activity.name
            }
        }
    }

    @Test func usedTodayIsMostRecentFirst() {
        #expect(catalog.usedToday == [1, 3, 2])
    }

    @Test func prefillIsTheFieldTextAndTheSelectedFirstRowAboveTodayAndEarlier() {
        let list = CheckInList(catalog: catalog, prefill: 2)
        #expect(list.text == "Writing")
        #expect(names(list) == ["Writing", "Code Review", "Weekly", "Planning"])
        #expect(
            list.rows.map { if case .activity(_, let today) = $0 { today } else { false } } == [
                true, true, true, false,
            ])
        #expect(list.showsSections)
        #expect(list.choice == .existing(2))
        #expect(list.fieldMatch?.activity.id == 2)
    }

    @Test func suggestionsCarryProjectAndCustomer() {
        let list = CheckInList(catalog: catalog, prefill: 1)
        guard case .activity(let suggestion, _) = list.rows[0] else {
            Issue.record("no activity row")
            return
        }
        #expect(suggestion.projectName == "Relaunch")
        #expect(suggestion.customerName == "Acme")
        #expect(catalog.customer(of: suggestion.activity)?.name == "Acme")
    }

    @Test func writingBackTheUnchangedTextKeepsTheListUnfiltered() {
        var list = CheckInList(catalog: catalog, prefill: 2)
        list.moveSelection(by: 1)
        list.setText("Writing")
        #expect(names(list) == ["Writing", "Code Review", "Weekly", "Planning"])
        #expect(list.showsSections)
        #expect(list.choice == .existing(1))
    }

    @Test func arrowsMoveTheSelectionWithinTheRows() {
        var list = CheckInList(catalog: catalog, prefill: 1)
        list.moveSelection(by: 1)
        #expect(list.choice == .existing(3))
        #expect(list.fieldMatch == nil)
        list.moveSelection(by: 10)
        #expect(list.choice == .existing(4))
        list.moveSelection(by: -10)
        #expect(list.choice == .existing(1))
    }

    @Test func typingFiltersOverActivityProjectAndCustomerWithoutSections() {
        var list = CheckInList(catalog: catalog, prefill: 1)
        list.setText("north")
        #expect(names(list) == ["+north", "Weekly", "Planning"])
        #expect(!list.showsSections)
    }

    @Test func anUnknownNameOffersCreateAsTheSelectedFirstRow() {
        var list = CheckInList(catalog: catalog, prefill: 1)
        list.setText("  Kickoff  ")
        #expect(names(list) == ["+Kickoff"])
        #expect(list.isCreating)
        #expect(list.choice == .create(name: "Kickoff", projectId: nil))
        list.projectId = 10
        #expect(list.choice == .create(name: "Kickoff", projectId: 10))
    }

    @Test func anExactNameIgnoringCaseSelectsThatActivityOnTopWithoutCreate() {
        var list = CheckInList(catalog: catalog, prefill: 1)
        list.setText("planning")
        #expect(names(list).first == "Planning")
        #expect(!list.isCreating)
        #expect(list.choice == .existing(4))
        #expect(list.fieldMatch?.activity.id == 4)
    }

    @Test func typingBreakChoosesTheBuiltInBreak() {
        var list = CheckInList(catalog: catalog, prefill: 1)
        list.setText("break")
        #expect(list.choice == .existing(100))
        #expect(!list.isCreating)
    }

    @Test func withBuiltInsBreakLeadsAndPrivateClosesTheList() {
        let list = CheckInList(catalog: catalog, prefill: 100, includingBuiltIns: true)
        #expect(list.text == "Break")
        #expect(names(list) == ["Break", "Code Review", "Weekly", "Writing", "Planning", "Private"])
        #expect(list.choice == .existing(100))
    }

    @Test func withBuiltInsTypingFindsPrivate() {
        var list = CheckInList(catalog: catalog, prefill: 100, includingBuiltIns: true)
        list.setText("priv")
        #expect(names(list).contains("Private"))
        list.setText("private")
        #expect(list.choice == .existing(101))
    }

    @Test func clearingTheFieldListsEverythingInSections() {
        var list = CheckInList(catalog: catalog, prefill: 2)
        list.setText("")
        #expect(names(list) == ["Code Review", "Weekly", "Writing", "Planning"])
        #expect(list.showsSections)
        #expect(list.choice == nil)
    }

    @Test func anEmptyFieldSelectsNothingUntilAnArrowKey() {
        var list = CheckInList(catalog: catalog, prefill: nil)
        #expect(list.text == "")
        #expect(names(list) == ["Code Review", "Weekly", "Writing", "Planning"])
        #expect(list.selection == nil)
        #expect(list.choice == nil)
        list.moveSelection(by: 1)
        #expect(list.choice == .existing(1))
        list.setText("  ")
        #expect(list.choice == nil)
        list.moveSelection(by: -1)
        #expect(list.choice == .existing(1))
    }

    @Test func atMostSixRowsIncludingCreate() {
        let many = Catalog(activities: (1...10).map { Activity(id: Int64($0), name: "Task \($0)") })
        #expect(CheckInList(catalog: many, prefill: nil).rows.count == CheckInList.maxRows)
        var list = CheckInList(catalog: many, prefill: nil)
        list.setText("Task")
        #expect(list.rows.count == CheckInList.maxRows)
        #expect(list.rows.last == .create(name: "Task"))
    }

    // MARK: Selection like Spotlight

    private let spotlight = Catalog(activities: [
        Activity(id: 1, name: "Code Review", lastUsedAt: Fixture.at("10:00")),
        Activity(id: 2, name: "Weekly", lastUsedAt: Fixture.at("09:00")),
        Activity(id: 3, name: "Kickoff Shop-Migration", lastUsedAt: Fixture.at("08:00")),
        Activity(id: 4, name: "Überarbeitung", lastUsedAt: Fixture.at("07:00")),
    ])

    private func typed(_ text: String) -> CheckInList {
        var list = CheckInList(catalog: spotlight, prefill: 1)
        list.setText(text)
        return list
    }

    @Test func aNameStartingWithTheTextIsSelectedAboveCreate() {
        let list = typed("wee")
        #expect(names(list) == ["Weekly", "+wee"])
        #expect(list.choice == .existing(2))
        #expect(!list.isCreating)
    }

    @Test func everyWordMustStartAWordOfTheName() {
        #expect(typed("code rev").choice == .existing(1))
        #expect(typed("kickoff mig").choice == .existing(3))
        let list = typed("Kickoff Relaunch")
        #expect(list.choice == .create(name: "Kickoff Relaunch", projectId: nil))
        #expect(list.rows.first == .create(name: "Kickoff Relaunch"))
    }

    @Test func wordPrefixesIgnoreCaseAndDiacritics() {
        #expect(typed("uber").choice == .existing(4))
        #expect(typed("WEEK").choice == .existing(2))
    }

    @Test func withoutAWordPrefixCreateStaysSelectedOnTop() {
        let list = typed("view")
        #expect(names(list) == ["+view", "Code Review"])
        #expect(list.isCreating)
    }

    @Test func aMatchBelowTheVisibleRowsMovesUpAboveCreate() {
        let previews = (1...6).map {
            Activity(id: Int64($0), name: "Preview \($0)", lastUsedAt: Fixture.at("10:0\($0)"))
        }
        let catalog = Catalog(activities: previews + [Activity(id: 7, name: "Review", lastUsedAt: Fixture.at("08:00"))])
        var list = CheckInList(catalog: catalog, prefill: nil)
        list.setText("rev")
        #expect(list.rows.count == CheckInList.maxRows)
        #expect(list.selection == CheckInList.maxRows - 2)
        #expect(list.choice == .existing(7))
        #expect(list.rows.last == .create(name: "rev"))
    }

    @Test func theFirstOfSeveralMatchesInSuggestionOrderIsSelected() {
        let catalog = Catalog(activities: [
            Activity(id: 1, name: "Writing docs", lastUsedAt: Fixture.at("08:00")),
            Activity(id: 2, name: "Writing", lastUsedAt: Fixture.at("09:00")),
        ])
        var list = CheckInList(catalog: catalog, prefill: nil)
        list.setText("wri")
        #expect(names(list) == ["Writing", "Writing docs", "+wri"])
        #expect(list.choice == .existing(2))
    }

    @Test func anArchivedPrefillStaysSelectable() {
        let list = CheckInList(catalog: catalog, prefill: 5)
        #expect(names(list).first == "Old Stuff")
        #expect(list.choice == .existing(5))
    }

    @Test func withoutRowsNothingIsChosen() {
        var list = CheckInList(catalog: Catalog(), prefill: nil)
        list.moveSelection(by: 1)
        #expect(list.text == "")
        #expect(list.selection == nil)
        #expect(list.choice == nil)
    }
}
