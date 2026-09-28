//
//  TreeMoveCRDTTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct TreeMoveCRDTTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    /// Creates a tree CRDT pre-seeded with initial parent relationships.
    private func makeTree(_ parentMap: [String: String?]) -> TreeMoveCRDT {
        TreeMoveCRDT(initialParentMap: parentMap)
    }

    // MARK: - Simple move

    @Test("Move node from root to child of another node")
    func simpleMoveToChild() {
        // A and B both at root
        var tree = makeTree(["A": nil, "B": nil])

        let accepted = tree.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: "B"
        ))

        #expect(accepted == true)
        #expect(tree.parentMap["A"] == "B")
    }

    @Test("Move node to root")
    func moveToRoot() {
        // A is child of B
        var tree = makeTree(["A": "B", "B": nil])

        let accepted = tree.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: nil
        ))

        #expect(accepted == true)
        #expect(tree.parentMap["A"] == String?.none)
    }

    // MARK: - Cycle detection

    @Test("Cycle detection: move parent under child is rejected")
    func cycleDetection() {
        // B is child of A
        var tree = makeTree(["A": nil, "B": "A"])

        let accepted = tree.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: "B"
        ))

        #expect(accepted == false)
        #expect(tree.parentMap["A"] == String?.none) // unchanged
    }

    @Test("Three-node cycle detection: A→B→C, move C under A would create cycle")
    func threeNodeCycleDetection() {
        // C under B, B under A
        var tree = makeTree(["A": nil, "B": "A", "C": "B"])

        let accepted = tree.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: "C"
        ))

        #expect(accepted == false)
    }

    // MARK: - Concurrent cycle-creating moves (CRITICAL)

    @Test("Concurrent cycle: peer1 moves A under B, peer2 moves B under A — both converge")
    func concurrentCycleConvergence() {
        let move1 = TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: "B"
        )
        let move2 = TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerB),
            nodeID: "B",
            newParentID: "A"
        )

        // Replica 1: apply move1 then move2
        var tree1 = makeTree(["A": nil, "B": nil])
        tree1.applyMove(move1)
        tree1.applyMove(move2)

        // Replica 2: apply move2 then move1
        var tree2 = makeTree(["A": nil, "B": nil])
        tree2.applyMove(move2)
        tree2.applyMove(move1)

        // Both must converge to the same parentMap
        #expect(tree1.parentMap == tree2.parentMap)
    }

    @Test("Concurrent cycle: one move accepted, one rejected")
    func concurrentCycleOneRejected() {
        let move1 = TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: "B"
        )
        let move2 = TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 2, peerID: peerB),
            nodeID: "B",
            newParentID: "A"
        )

        var tree = makeTree(["A": nil, "B": nil])
        tree.applyMove(move1)
        tree.applyMove(move2)

        // After both applied: one should create a cycle, the other accepted
        // They can't both be accepted without a cycle
        let aParent = tree.parentMap["A"]
        let bParent = tree.parentMap["B"]

        // If A is under B, B can't be under A (and vice versa)
        let hasCycle = (aParent == "B" && bParent == "A")
        #expect(hasCycle == false)
    }

    // MARK: - Late-arriving operation triggers rebuild

    @Test("Late-arriving op triggers rebuild and produces correct state")
    func lateArrivingOpRebuilds() {
        var tree = makeTree(["A": nil, "B": nil, "C": nil])

        // Apply op at time 3 first
        tree.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 3, peerID: peerA),
            nodeID: "C",
            newParentID: "B"
        ))

        // Apply op at time 2 (late-arriving — must trigger rebuild)
        tree.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 2, peerID: peerA),
            nodeID: "A",
            newParentID: "B"
        ))

        // Both A and C should be under B
        #expect(tree.parentMap["A"] == "B")
        #expect(tree.parentMap["C"] == "B")
    }

    @Test("Late-arriving op that would create cycle is rejected on rebuild")
    func lateArrivingCycleRejected() {
        // Start: A at root, B at root
        var tree1 = makeTree(["A": nil, "B": nil])
        var tree2 = makeTree(["A": nil, "B": nil])

        let moveAUnderB = TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: "B"
        )
        let moveBUnderA = TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 2, peerID: peerB),
            nodeID: "B",
            newParentID: "A"
        )

        // Tree1: sees move1 then move2
        tree1.applyMove(moveAUnderB)
        tree1.applyMove(moveBUnderA)

        // Tree2: sees move2 first (late), then move1 (late, triggers rebuild)
        tree2.applyMove(moveBUnderA)
        tree2.applyMove(moveAUnderB)

        // Must converge
        #expect(tree1.parentMap == tree2.parentMap)
    }

    // MARK: - Move to root is always safe

    @Test("Move to root never creates a cycle")
    func moveToRootNeverCycles() {
        var tree = makeTree(["A": "B", "B": nil])

        let accepted = tree.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: Timestamp(time: 1, peerID: peerA),
            nodeID: "A",
            newParentID: nil
        ))

        #expect(accepted == true)
        #expect(tree.parentMap["A"] == String?.none)
    }
}
