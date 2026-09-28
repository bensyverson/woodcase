//
//  RGAList.swift
//  Woodcase
//

import Foundation

/// A unique position identifier within an ``RGAList``, wrapping a ``Timestamp``.
///
/// Each insert operation produces a unique `PositionID` derived from the
/// operation's timestamp. This ID is stable across replicas and survives
/// tombstoning, making it safe to reference even after deletion.
public struct PositionID: Friendly, Comparable {
    /// The timestamp that created this position.
    public let timestamp: Timestamp

    /// Creates a position ID from a timestamp.
    ///
    /// - Parameter timestamp: The originating operation's timestamp.
    public init(timestamp: Timestamp) {
        self.timestamp = timestamp
    }

    public static func < (lhs: PositionID, rhs: PositionID) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}

/// A Replicated Growable Array — an ordered list CRDT supporting concurrent inserts.
///
/// Each element is assigned a unique ``PositionID`` at insertion time. Deletions
/// are implemented as tombstones (the entry is marked deleted but retained in the
/// internal structure) so that concurrent inserts relative to deleted positions
/// still converge correctly.
///
/// ## Ordering Rule
///
/// When two elements are inserted after the same predecessor, the one with the
/// **higher** ``PositionID`` (newer timestamp / higher peer ID) appears **first**
/// (leftmost). This produces deterministic interleaving across all replicas.
///
/// ## Usage
///
/// ```swift
/// var list = RGAList<String>()
/// let pos = list.insert("A", after: nil, timestamp: ts1)
/// list.insert("B", after: pos, timestamp: ts2)
/// print(list.elements) // ["A", "B"]
/// ```
public struct RGAList<Element: Friendly>: Friendly {
    /// A single entry in the list, which may be live or tombstoned.
    struct Entry: Friendly {
        var positionID: PositionID
        var value: Element
        var isDeleted: Bool
        var afterID: PositionID?
    }

    /// The internal storage, maintained in display order.
    private(set) var entries: [Entry]

    /// Creates an empty RGA list.
    public init() {
        entries = []
    }

    /// The live (non-tombstoned) elements in order.
    public var elements: [Element] {
        entries.filter { !$0.isDeleted }.map(\.value)
    }

    /// The number of live elements.
    public var count: Int {
        entries.count(where: { !$0.isDeleted })
    }

    /// Inserts an element after the given position.
    ///
    /// - Parameters:
    ///   - value: The element to insert.
    ///   - afterID: The position to insert after, or `nil` for the beginning.
    ///   - timestamp: The operation's timestamp (becomes the new ``PositionID``).
    /// - Returns: The position ID of the newly inserted element.
    @discardableResult
    public mutating func insert(_ value: Element, after afterID: PositionID?, timestamp: Timestamp) -> PositionID {
        let newPosID = PositionID(timestamp: timestamp)
        let entry = Entry(positionID: newPosID, value: value, isDeleted: false, afterID: afterID)

        // Find insertion point
        let startIndex: Int
        if let afterID {
            // Find the predecessor (may be tombstoned — that's fine)
            if let predIdx = entries.firstIndex(where: { $0.positionID == afterID }) {
                startIndex = predIdx + 1
            } else {
                // Predecessor not found — append at end
                entries.append(entry)
                return newPosID
            }
        } else {
            startIndex = 0
        }

        // Scan right past entries that were also inserted after the same predecessor
        // and have a higher position ID (they go first — newer leftmost).
        // Also skip descendants of those higher-priority siblings, since they
        // form a contiguous chain that must stay together.
        var insertIdx = startIndex
        var skippedPositions = Set<PositionID>()
        while insertIdx < entries.count {
            let existing = entries[insertIdx]
            if existing.afterID == afterID {
                // Concurrent sibling: skip if higher priority
                if existing.positionID > newPosID {
                    skippedPositions.insert(existing.positionID)
                    insertIdx += 1
                } else {
                    break
                }
            } else if let existingAfterID = existing.afterID, skippedPositions.contains(existingAfterID) {
                // Descendant of a skipped sibling — skip it too
                skippedPositions.insert(existing.positionID)
                insertIdx += 1
            } else {
                break
            }
        }

        entries.insert(entry, at: insertIdx)
        return newPosID
    }

    /// Inserts an element at the given visible index.
    ///
    /// - Parameters:
    ///   - value: The element to insert.
    ///   - index: The index in the visible (non-tombstoned) elements.
    ///   - timestamp: The operation's timestamp.
    /// - Returns: The position ID of the newly inserted element.
    @discardableResult
    public mutating func insertAtIndex(_ value: Element, index: Int, timestamp: Timestamp) -> PositionID {
        if index == 0 {
            return insert(value, after: nil, timestamp: timestamp)
        }
        guard let predPos = positionID(atIndex: index - 1) else {
            // Index out of range — append
            return insert(value, after: entries.last(where: { !$0.isDeleted })?.positionID, timestamp: timestamp)
        }
        return insert(value, after: predPos, timestamp: timestamp)
    }

    /// Tombstones the entry with the given position ID.
    ///
    /// - Parameter positionID: The position to delete.
    public mutating func delete(positionID: PositionID) {
        if let idx = entries.firstIndex(where: { $0.positionID == positionID }) {
            entries[idx].isDeleted = true
        }
    }

    /// Tombstones the entry at the given visible index.
    ///
    /// - Parameter index: The index in the visible (non-tombstoned) elements.
    public mutating func deleteAtIndex(_ index: Int) {
        if let posID = positionID(atIndex: index) {
            delete(positionID: posID)
        }
    }

    /// Moves an element to a new position (delete + re-insert).
    ///
    /// - Parameters:
    ///   - positionID: The element to move.
    ///   - afterID: The new predecessor, or `nil` for the beginning.
    ///   - timestamp: The operation's timestamp.
    /// - Returns: The new position ID for the moved element.
    @discardableResult
    public mutating func move(positionID: PositionID, after afterID: PositionID?, timestamp: Timestamp) -> PositionID {
        guard let idx = entries.firstIndex(where: { $0.positionID == positionID }) else {
            return PositionID(timestamp: timestamp)
        }
        let value = entries[idx].value
        entries[idx].isDeleted = true
        return insert(value, after: afterID, timestamp: timestamp)
    }

    /// Returns the position ID of the element at the given visible index.
    ///
    /// - Parameter index: The index in the visible (non-tombstoned) elements.
    /// - Returns: The position ID, or `nil` if the index is out of range.
    public func positionID(atIndex index: Int) -> PositionID? {
        var visibleCount = 0
        for entry in entries {
            if !entry.isDeleted {
                if visibleCount == index {
                    return entry.positionID
                }
                visibleCount += 1
            }
        }
        return nil
    }

    /// Returns the value of the entry with the given position ID, regardless of tombstone status.
    ///
    /// - Parameter positionID: The position to look up.
    /// - Returns: The element value, or `nil` if no entry has that position.
    public func value(at positionID: PositionID) -> Element? {
        entries.first(where: { $0.positionID == positionID })?.value
    }

    /// Returns the visible index of the element with the given position ID.
    ///
    /// - Parameter positionID: The position to look up.
    /// - Returns: The visible index, or `nil` if not found or tombstoned.
    public func visibleIndex(of positionID: PositionID) -> Int? {
        var visibleCount = 0
        for entry in entries {
            if entry.positionID == positionID {
                return entry.isDeleted ? nil : visibleCount
            }
            if !entry.isDeleted {
                visibleCount += 1
            }
        }
        return nil
    }
}
