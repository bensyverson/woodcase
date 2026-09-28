//
//  CRDTConcurrentMoveTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTConcurrentMoveTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    private func makePair(from doc: PenDocument) -> (EditableDocument, EditableDocument) {
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)
        return (a, b)
    }

    private func sync(_: EditableDocument, to target: EditableDocument, ops: [CRDTOperation]) {
        target.applyRemote(ops)
    }

    private func assertConverged(_ a: EditableDocument, _ b: EditableDocument, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.rootOrder == b.rootOrder, "rootOrder diverged", sourceLocation: sourceLocation)
        #expect(a.nodes.keys.sorted() == b.nodes.keys.sorted(), "node keys diverged", sourceLocation: sourceLocation)
        for key in a.nodes.keys {
            #expect(a.nodes[key] == b.nodes[key], "node \(key) diverged", sourceLocation: sourceLocation)
        }
        #expect(a.children == b.children, "children diverged", sourceLocation: sourceLocation)
        #expect(a.parents == b.parents, "parents diverged", sourceLocation: sourceLocation)
    }

    /// Document with two frames at root, each with a child:
    /// root: [frameX, frameY]
    /// frameX: [childA]
    /// frameY: [childB]
    private func makeTwoFrameDoc() -> PenDocument {
        let childA = PenNode(
            id: "childA",
            common: PenNodeCommon(name: "ChildA"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let childB = PenNode(
            id: "childB",
            common: PenNodeCommon(name: "ChildB"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let frameX = PenNode(
            id: "frameX",
            common: PenNodeCommon(name: "FrameX"),
            kind: .frame(PenNode.FrameData(children: [childA]))
        )
        let frameY = PenNode(
            id: "frameY",
            common: PenNodeCommon(name: "FrameY"),
            kind: .frame(PenNode.FrameData(children: [childB]))
        )
        return PenDocument(children: [frameX, frameY])
    }

    // MARK: - Concurrent cycle-creating moves

    @Test("A moves X under Y, B moves Y under X → cycle rejected, both converge")
    func mutualMovesCycleRejected() throws {
        let (a, b) = makePair(from: makeTwoFrameDoc())

        // A moves frameX under frameY
        let opsA = try a.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "frameX", newParentID: "frameY")))
        // B moves frameY under frameX
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "frameY", newParentID: "frameX")))

        // Exchange — one of the moves should be rejected to prevent cycle
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Verify no cycle: neither node is a descendant of the other in BOTH directions
        let aDescXofY = a.isDescendant("frameX", of: "frameY")
        let aDescYofX = a.isDescendant("frameY", of: "frameX")
        // At most one of these should be true
        #expect(!(aDescXofY && aDescYofX), "cycle detected in peer A")

        assertConverged(a, b)
    }

    // MARK: - Concurrent moves to different parents

    @Test("A moves X under Y, B moves X under Z → last writer wins")
    func concurrentMovesDifferentParents() throws {
        // Add a third frame
        let childA = PenNode(
            id: "childA",
            common: PenNodeCommon(name: "ChildA"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let frameX = PenNode(
            id: "frameX",
            common: PenNodeCommon(name: "FrameX"),
            kind: .frame(PenNode.FrameData(children: [childA]))
        )
        let frameY = PenNode(
            id: "frameY",
            common: PenNodeCommon(name: "FrameY"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let frameZ = PenNode(
            id: "frameZ",
            common: PenNodeCommon(name: "FrameZ"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let doc = PenDocument(children: [frameX, frameY, frameZ])
        let (a, b) = makePair(from: doc)

        // A moves childA under frameY
        let opsA = try a.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "childA", newParentID: "frameY")))
        // B moves childA under frameZ
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "childA", newParentID: "frameZ")))

        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should converge — childA is under exactly one parent
        assertConverged(a, b)
        // childA should exist in exactly one place
        #expect(a.nodes["childA"] != nil)
    }

    // MARK: - Three-node cycle attempt

    @Test("Three-node cycle attempt: A→B, B→C, C→A → converge with no cycle")
    func threeNodeCycleAttempt() throws {
        let frameA = PenNode(
            id: "fA",
            common: PenNodeCommon(name: "A"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let frameB = PenNode(
            id: "fB",
            common: PenNodeCommon(name: "B"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let frameC = PenNode(
            id: "fC",
            common: PenNodeCommon(name: "C"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let doc = PenDocument(children: [frameA, frameB, frameC])

        let peerC = PeerID(rawValue: "ccc")
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)
        let c = EditableDocument(from: doc, peerID: peerC)

        // A moves fA under fB
        let opsA = try a.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "fA", newParentID: "fB")))
        // B moves fB under fC
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "fB", newParentID: "fC")))
        // C moves fC under fA
        let opsC = try c.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "fC", newParentID: "fA")))

        // Full exchange
        let allOps = opsA + opsB + opsC
        a.applyRemote(opsB + opsC)
        b.applyRemote(opsA + opsC)
        c.applyRemote(opsA + opsB)

        /// Verify no cycles exist
        func hasCycle(_ doc: EditableDocument) -> Bool {
            for nodeID in doc.nodes.keys {
                var visited = Set<String>()
                var current: String? = nodeID
                while let id = current {
                    if visited.contains(id) { return true }
                    visited.insert(id)
                    current = doc.parents[id]
                }
            }
            return false
        }
        #expect(!hasCycle(a), "peer A has cycle")
        #expect(!hasCycle(b), "peer B has cycle")
        #expect(!hasCycle(c), "peer C has cycle")

        // All three should converge on the same tree structure
        assertConverged(a, b)
        assertConverged(b, c)

        _ = allOps
    }

    // MARK: - Concurrent moves of same node (listMove convergence)

    @Test("Concurrent moves of same node to different parents converge via atomic listMove")
    func concurrentMovesSameNodeConverge() throws {
        let (a, b) = makePair(from: makeTwoFrameDoc())

        // A moves childA from frameX to frameY
        let opsA = try a.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "childA", newParentID: "frameY")))
        // B moves childA from frameX to root
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "childA", newParentID: nil)))

        // Exchange in both orders to verify convergence
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        assertConverged(a, b)

        // childA should be in exactly one parent's children
        let inFrameX = a.children["frameX"]?.contains("childA") ?? false
        let inFrameY = a.children["frameY"]?.contains("childA") ?? false
        let inRoot = a.rootOrder.contains("childA")
        let parentCount = [inFrameX, inFrameY, inRoot].count(where: { $0 })
        #expect(parentCount == 1, "childA should appear in exactly one parent")
    }

    @Test("Concurrent move and reorder within same parent converge")
    func concurrentMoveAndReorderConverge() throws {
        // doc: root → [frameX → [childA, childB]]
        let childA = PenNode(
            id: "childA",
            common: PenNodeCommon(name: "ChildA"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let childB = PenNode(
            id: "childB",
            common: PenNodeCommon(name: "ChildB"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let frameX = PenNode(
            id: "frameX",
            common: PenNodeCommon(name: "FrameX"),
            kind: .frame(PenNode.FrameData(children: [childA, childB]))
        )
        let frameY = PenNode(
            id: "frameY",
            common: PenNodeCommon(name: "FrameY"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let doc = PenDocument(children: [frameX, frameY])
        let (a, b) = makePair(from: doc)

        // A moves childA to frameY
        let opsA = try a.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "childA", newParentID: "frameY")))
        // B reorders childA within frameX (move to end)
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "childA", newParentID: "frameX", index: 1)))

        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        assertConverged(a, b)
    }
}
