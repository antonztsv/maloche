import Foundation
import Testing

@testable import MalocheCore

@Suite struct TimelineTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ minutes: Double) -> Date {
        base.addingTimeInterval(minutes * 60)
    }

    private func block(
        _ id: Int64?, _ from: Double, _ to: Double, activity: Int64 = 1, source: BlockSource = .checkIn
    ) -> Block {
        Block(id: id, activityId: activity, startedAt: at(from), endedAt: at(to), source: source)
    }

    @Test func noOverlapOnlyInsertsNewBlock() {
        let new = block(nil, 60, 90, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 0, 30)])
        #expect(changes == TimelineChanges(updated: [], inserted: [new], deletedIds: []))
    }

    @Test func touchingBlocksDoNotOverlap() {
        let new = block(nil, 30, 60, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 0, 30), block(2, 60, 90)])
        #expect(changes == TimelineChanges(updated: [], inserted: [new], deletedIds: []))
    }

    @Test func existingBlockEndingInsideNewIsShortenedAtItsEnd() {
        let new = block(nil, 20, 50, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 0, 30)])
        #expect(changes == TimelineChanges(updated: [block(1, 0, 20)], inserted: [new], deletedIds: []))
    }

    @Test func existingBlockStartingInsideNewIsShortenedAtItsStart() {
        let new = block(nil, 20, 50, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 40, 70)])
        #expect(changes == TimelineChanges(updated: [block(1, 50, 70)], inserted: [new], deletedIds: []))
    }

    @Test func sharedStartShortensExistingAtItsStart() {
        let new = block(nil, 0, 20, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 0, 60)])
        #expect(changes == TimelineChanges(updated: [block(1, 20, 60)], inserted: [new], deletedIds: []))
    }

    @Test func sharedEndShortensExistingAtItsEnd() {
        let new = block(nil, 40, 60, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 0, 60)])
        #expect(changes == TimelineChanges(updated: [block(1, 0, 40)], inserted: [new], deletedIds: []))
    }

    @Test func newBlockInsideExistingSplitsItAndTailKeepsActivityAndSource() {
        let new = block(nil, 20, 30, activity: 2)
        let existing = block(1, 0, 60, activity: 7, source: .manual)
        let changes = Timeline.changes(inserting: new, into: [existing])
        let head = block(1, 0, 20, activity: 7, source: .manual)
        let tail = block(nil, 30, 60, activity: 7, source: .manual)
        #expect(changes == TimelineChanges(updated: [head], inserted: [new, tail], deletedIds: []))
    }

    @Test func newBlockCoveringExistingDeletesIt() {
        let new = block(nil, 10, 40, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 20, 30)])
        #expect(changes == TimelineChanges(updated: [], inserted: [new], deletedIds: [1]))
    }

    @Test func newBlockWithSameBoundsReplacesExisting() {
        let new = block(nil, 10, 40, activity: 2)
        let changes = Timeline.changes(inserting: new, into: [block(1, 10, 40)])
        #expect(changes == TimelineChanges(updated: [], inserted: [new], deletedIds: [1]))
    }

    @Test func newBlockCoveringSeveralDeletesAll() {
        let new = block(nil, 0, 50, activity: 2)
        let changes = Timeline.changes(
            inserting: new, into: [block(1, 10, 20), block(2, 20, 30), block(3, 30, 40)])
        #expect(changes == TimelineChanges(updated: [], inserted: [new], deletedIds: [1, 2, 3]))
    }

    @Test func combinationAcrossSeveralBlocks() {
        let new = block(nil, 10, 40, activity: 2)
        let existing = [block(1, 0, 20), block(2, 20, 30), block(3, 30, 60), block(4, 70, 80)]
        let changes = Timeline.changes(inserting: new, into: existing)
        #expect(
            changes
                == TimelineChanges(updated: [block(1, 0, 10), block(3, 40, 60)], inserted: [new], deletedIds: [2]))
    }

    @Test func blockIntervalSpansStartToEnd() {
        #expect(block(1, 0, 30).interval == DateInterval(start: at(0), end: at(30)))
    }
}
