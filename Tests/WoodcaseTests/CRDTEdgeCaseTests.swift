//
//  CRDTEdgeCaseTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTEdgeCaseTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")
    private let peerC = PeerID(rawValue: "ccc")

    // MARK: - Helpers

    private func makePair(from doc: PenDocument) -> (EditableDocument, EditableDocument) {
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)
        return (a, b)
    }

    private func makeTriple(from doc: PenDocument) -> (EditableDocument, EditableDocument, EditableDocument) {
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)
        let c = EditableDocument(from: doc, peerID: peerC)
        return (a, b, c)
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
        #expect(a.variables == b.variables, "variables diverged", sourceLocation: sourceLocation)
        #expect(a.imports == b.imports, "imports diverged", sourceLocation: sourceLocation)
        #expect(a.themes == b.themes, "themes diverged", sourceLocation: sourceLocation)
    }

    private func makeTestDoc() -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let text = PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Text"),
            kind: .text(PenNode.TextData(width: .fixed(200)))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect, text]))
        )
        return PenDocument(children: [frame])
    }

    // MARK: - Tests

    @Test("Out-of-order operation arrival")
    func outOfOrderOperationArrival() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // A does 3 property edits
        let ops1 = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "Step1")
        )))
        let ops2 = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "Step2")
        )))
        let ops3 = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "Step3")
        )))

        // Send to B out of order: [1, 3, 2]
        sync(a, to: b, ops: ops1)
        sync(a, to: b, ops: ops3)
        sync(a, to: b, ops: ops2)

        // B should have the LWW winner (Step3, highest timestamp)
        assertConverged(a, b)
    }

    @Test("Property edit on deleted node is silently ignored")
    func propertySetOnDeletedNode() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // A deletes r1
        let opsDeleteA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "r1")))

        // B edits r1's properties (doesn't know about delete yet)
        let opsEditB = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "EditedByB")
        )))

        // Exchange
        sync(a, to: b, ops: opsDeleteA)
        sync(b, to: a, ops: opsEditB)

        // r1 should be deleted on both — edit on deleted node is dropped
        #expect(a.nodes["r1"] == nil, "r1 should be deleted on A")
        #expect(b.nodes["r1"] == nil, "r1 should be deleted on B")
        assertConverged(a, b)
    }

    @Test("Same Lamport timestamp tie-breaking uses PeerID")
    func sameTimestampTieBreaking() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // Both peers rename r1 — since they start with the same clock state,
        // the first op from each will have the same Lamport time.
        // The PeerID breaks the tie deterministically.
        let opsA = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "NameByA")
        )))
        let opsB = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "NameByB")
        )))

        // Exchange in both directions
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both must converge to the same winner
        #expect(a.nodes["r1"]?.common.name == b.nodes["r1"]?.common.name,
                "Both peers should agree on the name")
        assertConverged(a, b)
    }

    @Test("Three-peer convergence with concurrent structural ops")
    func threePeerConvergence() throws {
        let (a, b, c) = makeTriple(from: makeTestDoc())

        // A inserts a new node
        let nodeA = PenNode(
            id: "nA",
            common: PenNodeCommon(name: "NodeA"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let opsA = try a.applyLocal(.insertNode(EditOperation.InsertNode(node: nodeA, parentID: "f1")))

        // B renames a node
        let opsB = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "RenamedByB")
        )))

        // C inserts another node
        let nodeC = PenNode(
            id: "nC",
            common: PenNodeCommon(name: "NodeC"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let opsC = try c.applyLocal(.insertNode(EditOperation.InsertNode(node: nodeC, parentID: "f1")))

        // Full exchange: everyone sends to everyone
        sync(a, to: b, ops: opsA)
        sync(a, to: c, ops: opsA)
        sync(b, to: a, ops: opsB)
        sync(b, to: c, ops: opsB)
        sync(c, to: a, ops: opsC)
        sync(c, to: b, ops: opsC)

        // All three should converge
        assertConverged(a, b)
        assertConverged(b, c)

        // All nodes should exist
        #expect(a.nodes["nA"] != nil, "A's insert should exist on all peers")
        #expect(a.nodes["nC"] != nil, "C's insert should exist on all peers")
        #expect(a.nodes["r1"]?.common.name == "RenamedByB", "B's rename should be applied")
    }

    @Test("Empty document: insert then delete")
    func emptyDocumentOperations() throws {
        let emptyDoc = PenDocument(children: [])
        let (a, b) = makePair(from: emptyDoc)

        let node = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "Node"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let opsInsert = try a.applyLocal(.insertNode(EditOperation.InsertNode(node: node)))
        sync(a, to: b, ops: opsInsert)

        #expect(b.nodes["n1"] != nil, "Insert should arrive")
        assertConverged(a, b)

        let opsDelete = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "n1")))
        sync(a, to: b, ops: opsDelete)

        #expect(a.nodes["n1"] == nil, "Node should be deleted on A")
        #expect(b.nodes["n1"] == nil, "Node should be deleted on B")
        assertConverged(a, b)
    }

    @Test("Single root node: rename and delete")
    func singleNodeOperations() throws {
        let node = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "Solo"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let doc = PenDocument(children: [node])
        let (a, b) = makePair(from: doc)

        // A renames
        let opsRename = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "n1", common: PenNodeCommon(name: "Renamed")
        )))
        sync(a, to: b, ops: opsRename)

        #expect(b.nodes["n1"]?.common.name == "Renamed")
        assertConverged(a, b)

        // A deletes
        let opsDelete = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "n1")))
        sync(a, to: b, ops: opsDelete)

        #expect(a.nodes.isEmpty, "A should be empty")
        #expect(b.nodes.isEmpty, "B should be empty")
        assertConverged(a, b)
    }

    @Test("Concurrent variable set and remove → LWW resolves deterministically")
    func concurrentVariableSetAndRemove() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // Both peers add the same variable first
        let varDef = PenVariable(type: .color, value: .simple(AnyCodable("#FF0000")))
        let opsSetupA = try a.applyLocal(.addVariable(EditOperation.AddVariable(name: "x", variable: varDef)))
        let opsSetupB = try b.applyLocal(.addVariable(EditOperation.AddVariable(name: "x", variable: varDef)))
        sync(a, to: b, ops: opsSetupA)
        sync(b, to: a, ops: opsSetupB)

        // A updates "x", B removes "x"
        let updatedVar = PenVariable(type: .color, value: .simple(AnyCodable("#00FF00")))
        let opsA = try a.applyLocal(.updateVariable(EditOperation.UpdateVariable(name: "x", variable: updatedVar)))
        let opsB = try b.applyLocal(.removeVariable(EditOperation.RemoveVariable(name: "x")))

        // Exchange
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should converge — LWW winner determined by timestamp
        assertConverged(a, b)
    }

    @Test("Insert after deleted sibling position handled gracefully")
    func insertAfterDeletedPosition() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // A deletes r1 (first child of f1)
        let opsDeleteA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "r1")))

        // B inserts a new node after r1's position in f1
        let newNode = PenNode(
            id: "new1",
            common: PenNodeCommon(name: "New"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let opsInsertB = try b.applyLocal(.insertNode(EditOperation.InsertNode(
            node: newNode, parentID: "f1"
        )))

        // Exchange
        sync(a, to: b, ops: opsDeleteA)
        sync(b, to: a, ops: opsInsertB)

        // Both should have the new node and not crash
        #expect(a.nodes["new1"] != nil, "new node should exist on A")
        #expect(b.nodes["new1"] != nil, "new node should exist on B")
        #expect(a.nodes["r1"] == nil, "r1 should be deleted")
        #expect(b.nodes["r1"] == nil, "r1 should be deleted")
        assertConverged(a, b)
    }

    @Test("Delete parent while moving child in → child survives at root")
    func deleteParentWhileMovingChildIn() throws {
        // Create doc: frame P with child C, and sibling frame Q
        let child = PenNode(
            id: "c1",
            common: PenNodeCommon(name: "Child"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let parentP = PenNode(
            id: "p1",
            common: PenNodeCommon(name: "ParentP"),
            kind: .frame(PenNode.FrameData(width: .fixed(200)))
        )
        let parentQ = PenNode(
            id: "q1",
            common: PenNodeCommon(name: "ParentQ"),
            kind: .frame(PenNode.FrameData(width: .fixed(200), children: [child]))
        )
        let doc = PenDocument(children: [parentP, parentQ])
        let (a, b) = makePair(from: doc)

        // A deletes P
        let opsDeleteA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "p1")))

        // B moves c1 into P
        let opsMoveB = try b.applyLocal(.moveNode(EditOperation.MoveNode(
            nodeID: "c1", newParentID: "p1"
        )))

        // Exchange
        sync(a, to: b, ops: opsDeleteA)
        sync(b, to: a, ops: opsMoveB)

        // P should be deleted. c1 should survive (promoted to root or re-parented).
        #expect(a.nodes["p1"] == nil, "P should be deleted")
        #expect(b.nodes["p1"] == nil, "P should be deleted")
        #expect(a.nodes["c1"] != nil, "c1 should survive on A")
        #expect(b.nodes["c1"] != nil, "c1 should survive on B")
        assertConverged(a, b)
    }
}
