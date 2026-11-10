import Foundation

public struct TimelineChanges: Equatable, Sendable {
    public var updated: [Block]
    public var inserted: [Block]
    public var deletedIds: [Int64]

    public init(updated: [Block], inserted: [Block], deletedIds: [Int64]) {
        self.updated = updated
        self.inserted = inserted
        self.deletedIds = deletedIds
    }
}

/// Keeps blocks free of overlaps: a new block wins over the existing blocks it overlaps.
public enum Timeline {
    public static func changes(inserting new: Block, into existing: [Block]) -> TimelineChanges {
        var changes = TimelineChanges(updated: [], inserted: [new], deletedIds: [])
        for var block in existing where block.startedAt < new.endedAt && new.startedAt < block.endedAt {
            let keepsHead = block.startedAt < new.startedAt
            let keepsTail = new.endedAt < block.endedAt
            switch (keepsHead, keepsTail) {
            case (false, false):
                if let id = block.id { changes.deletedIds.append(id) }
            case (true, true):
                var tail = block
                tail.id = nil
                tail.startedAt = new.endedAt
                changes.inserted.append(tail)
                block.endedAt = new.startedAt
                changes.updated.append(block)
            case (true, false):
                block.endedAt = new.startedAt
                changes.updated.append(block)
            case (false, true):
                block.startedAt = new.endedAt
                changes.updated.append(block)
            }
        }
        return changes
    }
}
