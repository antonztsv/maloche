import Foundation
import Testing

@testable import MalocheCore

@Suite struct SplitDraftTests {
    private let catalog = Catalog(activities: [
        Activity(id: 1, name: "Code Review"), Activity(id: 2, name: "Writing"), Activity(id: 3, name: "Weekly"),
    ])

    private func draft(_ start: String = "10:15", _ end: String = "11:00") -> SplitDraft {
        SplitDraft(
            span: Fixture.span(start, end), first: CheckInList(catalog: catalog, prefill: 1),
            second: CheckInList(catalog: catalog, prefill: 2))
    }

    private func clocks(_ draft: SplitDraft) -> [String] {
        draft.dividers.map(Fixture.clock)
    }

    @Test func twoPartsDividedInTheMiddleOnAWholeMinute() {
        let draft = draft()
        #expect(clocks(draft) == ["10:37"])
        #expect(draft.intervals == [Fixture.span("10:15", "10:37"), Fixture.span("10:37", "11:00")])
        #expect(draft.choices == [.existing(1), .existing(2)])
    }

    @Test func aDraggedDividerSnapsToTheNearestWholeMinute() {
        var draft = draft()
        draft.moveDivider(0, to: Fixture.at("10:40:20"))
        #expect(clocks(draft) == ["10:40"])
        draft.moveDivider(0, to: Fixture.at("10:40:40"))
        #expect(clocks(draft) == ["10:41"])
    }

    @Test func everyPartKeepsAtLeastOneMinute() {
        var draft = draft("10:15", "10:59:59")
        draft.moveDivider(0, to: Fixture.at("09:00"))
        #expect(clocks(draft) == ["10:16"])
        draft.moveDivider(0, to: Fixture.at("12:00"))
        #expect(clocks(draft) == ["10:58"])
        #expect(draft.intervals.allSatisfy { $0.duration >= 60 })
    }

    @Test func arrowKeysMoveTheDividerByAMinuteWithinItsBounds() {
        var draft = draft()
        draft.moveDivider(0, by: 1)
        #expect(clocks(draft) == ["10:38"])
        draft.moveDivider(0, to: Fixture.at("10:16"))
        draft.moveDivider(0, by: -1)
        #expect(clocks(draft) == ["10:16"])
    }

    @Test func anotherPartHalvesTheLastPart() {
        var draft = draft()
        draft.addPart(CheckInList(catalog: catalog, prefill: 3))
        #expect(clocks(draft) == ["10:37", "10:48"])
        #expect(draft.parts.count == 3)
        #expect(draft.choices == [.existing(1), .existing(2), .existing(3)])
    }

    @Test func dividersStayInOrderWithAMinuteBetweenThem() {
        var draft = draft()
        draft.addPart(CheckInList(catalog: catalog, prefill: 3))
        draft.moveDivider(0, to: Fixture.at("10:55"))
        #expect(clocks(draft) == ["10:47", "10:48"])
        draft.moveDivider(1, to: Fixture.at("10:20"))
        #expect(clocks(draft) == ["10:47", "10:48"])
        draft.moveDivider(1, by: 5)
        #expect(clocks(draft) == ["10:47", "10:53"])
    }

    @Test func aLastPartUnderTwoMinutesCannotBeHalved() {
        var draft = draft("10:15", "10:59:59")
        draft.moveDivider(0, to: Fixture.at("10:58"))
        #expect(draft.canAddPart == false)
        draft.addPart(CheckInList(catalog: catalog, prefill: 3))
        #expect(draft.parts.count == 2)
        draft.moveDivider(0, by: -1)
        #expect(draft.canAddPart)
        draft.addPart(CheckInList(catalog: catalog, prefill: 3))
        #expect(clocks(draft) == ["10:57", "10:58"])
        #expect(draft.intervals.allSatisfy { $0.duration >= 60 })
    }

    @Test func withoutAnActivityInEveryPartNothingIsChosen() {
        var draft = draft()
        draft.addPart(CheckInList(catalog: Catalog(), prefill: nil))
        #expect(draft.choices == nil)
    }
}
