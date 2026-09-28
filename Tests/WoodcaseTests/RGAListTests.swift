//
//  RGAListTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct RGAListTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    // MARK: - Basic insert

    @Test("Insert at beginning of empty list")
    func insertAtBeginning() {
        var list = RGAList<String>()
        list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        #expect(list.elements == ["A"])
    }

    @Test("Insert at end (after last element)")
    func insertAtEnd() {
        var list = RGAList<String>()
        let pos1 = list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        list.insert("B", after: pos1, timestamp: Timestamp(time: 2, peerID: peerA))
        #expect(list.elements == ["A", "B"])
    }

    @Test("Insert in middle")
    func insertInMiddle() {
        var list = RGAList<String>()
        let pos1 = list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let pos2 = list.insert("C", after: pos1, timestamp: Timestamp(time: 2, peerID: peerA))
        list.insert("B", after: pos1, timestamp: Timestamp(time: 3, peerID: peerA))
        _ = pos2
        #expect(list.elements == ["A", "B", "C"])
    }

    @Test("Insert by index")
    func insertByIndex() {
        var list = RGAList<String>()
        list.insertAtIndex("A", index: 0, timestamp: Timestamp(time: 1, peerID: peerA))
        list.insertAtIndex("C", index: 1, timestamp: Timestamp(time: 2, peerID: peerA))
        list.insertAtIndex("B", index: 1, timestamp: Timestamp(time: 3, peerID: peerA))
        #expect(list.elements == ["A", "B", "C"])
    }

    // MARK: - Delete

    @Test("Delete removes element but preserves structure (tombstone)")
    func deleteTombstone() {
        var list = RGAList<String>()
        let pos1 = list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let pos2 = list.insert("B", after: pos1, timestamp: Timestamp(time: 2, peerID: peerA))
        list.insert("C", after: pos2, timestamp: Timestamp(time: 3, peerID: peerA))

        list.delete(positionID: pos2)
        #expect(list.elements == ["A", "C"])
    }

    @Test("Delete by index")
    func deleteByIndex() throws {
        var list = RGAList<String>()
        list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let pos1 = list.positionID(atIndex: 0)
        try list.insert("B", after: #require(pos1), timestamp: Timestamp(time: 2, peerID: peerA))

        list.deleteAtIndex(0)
        #expect(list.elements == ["B"])
    }

    // MARK: - Concurrent inserts

    @Test("Concurrent inserts at same position: higher timestamp goes left")
    func concurrentInserts() {
        var list1 = RGAList<String>()
        var list2 = RGAList<String>()

        // Both insert at beginning
        let posA = list1.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let posB = list2.insert("B", after: nil, timestamp: Timestamp(time: 1, peerID: peerB))

        // Merge: apply other's insert to each
        list1.insert("B", after: nil, timestamp: Timestamp(time: 1, peerID: peerB))
        list2.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))

        _ = (posA, posB)

        // Both should converge to the same order
        #expect(list1.elements == list2.elements)
        // Higher peerID (bbb) goes left (newer first)
        #expect(list1.elements == ["B", "A"])
    }

    @Test("Concurrent inserts after same predecessor")
    func concurrentInsertsAfterSamePredecessor() {
        var list1 = RGAList<String>()
        var list2 = RGAList<String>()

        // Shared initial state: insert "X"
        let pos1 = list1.insert("X", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let pos2 = list2.insert("X", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))

        // peerA inserts "A" after "X" at time 2
        list1.insert("A", after: pos1, timestamp: Timestamp(time: 2, peerID: peerA))
        // peerB inserts "B" after "X" at time 2
        list2.insert("B", after: pos2, timestamp: Timestamp(time: 2, peerID: peerB))

        // Cross-apply
        list1.insert("B", after: pos1, timestamp: Timestamp(time: 2, peerID: peerB))
        list2.insert("A", after: pos2, timestamp: Timestamp(time: 2, peerID: peerA))

        // Should converge
        #expect(list1.elements == list2.elements)
        // Higher peerID goes left: B, A
        #expect(list1.elements == ["X", "B", "A"])
    }

    // MARK: - Insert after tombstone

    @Test("Insert after tombstoned element")
    func insertAfterTombstone() {
        var list = RGAList<String>()
        let pos1 = list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let pos2 = list.insert("B", after: pos1, timestamp: Timestamp(time: 2, peerID: peerA))

        list.delete(positionID: pos1)
        // Insert after the tombstoned "A" — should appear before "B"
        list.insert("C", after: pos1, timestamp: Timestamp(time: 3, peerID: peerA))

        _ = pos2
        #expect(list.elements == ["C", "B"])
    }

    // MARK: - Move

    @Test("Move within list (delete + re-insert)")
    func moveWithinList() throws {
        var list = RGAList<String>()
        let pos1 = list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let pos2 = list.insert("B", after: pos1, timestamp: Timestamp(time: 2, peerID: peerA))
        list.insert("C", after: pos2, timestamp: Timestamp(time: 3, peerID: peerA))

        // Move "A" to after "C" (effectively end)
        let newPos = try list.move(positionID: pos1, after: #require(list.positionID(atIndex: 2)), timestamp: Timestamp(time: 4, peerID: peerA))
        _ = newPos
        #expect(list.elements == ["B", "C", "A"])
    }

    // MARK: - Move to beginning

    @Test("Move element to beginning (after: nil)")
    func moveToBeginning() throws {
        var list = RGAList<String>()
        let pos1 = list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        let pos2 = list.insert("B", after: pos1, timestamp: Timestamp(time: 2, peerID: peerA))
        list.insert("C", after: pos2, timestamp: Timestamp(time: 3, peerID: peerA))

        // Move "C" to the beginning
        let posC = try #require(list.positionID(atIndex: 2))
        list.move(positionID: posC, after: nil, timestamp: Timestamp(time: 4, peerID: peerA))
        #expect(list.elements == ["C", "A", "B"])
    }

    // MARK: - Value lookup by PositionID

    @Test("value(at:) returns element value for live entry")
    func valueAtLiveEntry() {
        var list = RGAList<String>()
        let pos = list.insert("Hello", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        #expect(list.value(at: pos) == "Hello")
    }

    @Test("value(at:) returns element value for tombstoned entry")
    func valueAtTombstonedEntry() {
        var list = RGAList<String>()
        let pos = list.insert("Hello", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        list.delete(positionID: pos)
        #expect(list.value(at: pos) == "Hello")
    }

    @Test("value(at:) returns nil for unknown position")
    func valueAtUnknownPosition() {
        let list = RGAList<String>()
        let unknownPos = PositionID(timestamp: Timestamp(time: 99, peerID: peerA))
        #expect(list.value(at: unknownPos) == nil)
    }

    // MARK: - Empty list

    @Test("Empty list has no elements")
    func emptyList() {
        let list = RGAList<String>()
        #expect(list.elements.isEmpty)
    }

    // MARK: - Convergence

    @Test("Two RGA instances with same ops in different orders converge")
    func convergence() {
        var list1 = RGAList<String>()
        var list2 = RGAList<String>()

        let ts1 = Timestamp(time: 1, peerID: peerA)
        let ts2 = Timestamp(time: 2, peerID: peerA)
        let ts3 = Timestamp(time: 3, peerID: peerB)

        // List 1: apply in order 1, 2, 3
        let p1a = list1.insert("A", after: nil, timestamp: ts1)
        list1.insert("B", after: p1a, timestamp: ts2)
        list1.insert("C", after: p1a, timestamp: ts3)

        // List 2: apply in order 3, 1, 2
        let p2a = list2.insert("A", after: nil, timestamp: ts1)
        list2.insert("C", after: p2a, timestamp: ts3)
        list2.insert("B", after: p2a, timestamp: ts2)

        #expect(list1.elements == list2.elements)
    }

    // MARK: - Position lookups

    @Test("positionID(atIndex:) returns correct position")
    func positionIDAtIndex() {
        var list = RGAList<String>()
        let pos = list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        #expect(list.positionID(atIndex: 0) == pos)
        #expect(list.positionID(atIndex: 1) == nil)
    }

    @Test("RGAList is Friendly")
    func isFriendly() throws {
        var list = RGAList<String>()
        list.insert("A", after: nil, timestamp: Timestamp(time: 1, peerID: peerA))
        try list.insert("B", after: #require(list.positionID(atIndex: 0)), timestamp: Timestamp(time: 2, peerID: peerA))

        let data = try JSONEncoder().encode(list)
        let decoded = try JSONDecoder().decode(RGAList<String>.self, from: data)
        #expect(decoded.elements == list.elements)
    }
}
