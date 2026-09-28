//
//  CRDTConcurrentDeleteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTConcurrentDeleteTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    private func makePair(from doc: PenDocument) -> (EditableDocument, EditableDocument) {
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)
        return (a, b)
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

    private func makeDoc() -> PenDocument {
        let child = PenNode(
            id: "child",
            common: PenNodeCommon(name: "Child"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let parent = PenNode(
            id: "parent",
            common: PenNodeCommon(name: "Parent"),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        return PenDocument(children: [parent])
    }

    // MARK: - A deletes X, B edits X

    @Test("A deletes node, B edits it → edit dropped, both converge")
    func deleteVsEditDropsEdit() throws {
        let (a, b) = makePair(from: makeDoc())

        // A deletes child
        let opsA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "child")))

        // B renames child
        let opsB = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "child",
            common: PenNodeCommon(name: "RenamedByB")
        )))

        // Exchange
        a.applyRemote(opsB)
        b.applyRemote(opsA)

        // child should be gone on both (delete wins over concurrent edit)
        #expect(a.nodes["child"] == nil)
        #expect(b.nodes["child"] == nil)
        assertConverged(a, b)
    }

    // MARK: - A deletes parent, B moves child into parent

    @Test("A deletes parent, B moves child into parent → delete wins, both converge")
    func deleteParentVsMoveChildIntoParent() throws {
        // Setup: two frames, one child
        let child = PenNode(
            id: "child",
            common: PenNodeCommon(name: "Child"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let frame1 = PenNode(
            id: "frame1",
            common: PenNodeCommon(name: "Frame1"),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        let frame2 = PenNode(
            id: "frame2",
            common: PenNodeCommon(name: "Frame2"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let doc = PenDocument(children: [frame1, frame2])
        let (a, b) = makePair(from: doc)

        // A deletes frame2
        let opsA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "frame2")))

        // B moves child into frame2
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "child", newParentID: "frame2")))

        // Exchange
        a.applyRemote(opsB)
        b.applyRemote(opsA)

        // frame2 should be gone on both
        #expect(a.nodes["frame2"] == nil)
        #expect(b.nodes["frame2"] == nil)

        // Delete-wins semantic: when a node is deleted and a concurrent move
        // targets it, the delete takes precedence. The moved child is lost
        // along with the deleted parent. Both peers must converge.
        assertConverged(a, b)
    }

    // MARK: - A deletes parent, B inserts child into parent

    @Test("A deletes parent, B inserts new child into parent → delete wins, both converge")
    func deleteParentVsInsertChild() throws {
        let (a, b) = makePair(from: makeDoc())

        // A deletes parent frame
        let opsA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "parent")))

        // B inserts new node into parent
        let newNode = PenNode(
            id: "newChild",
            common: PenNodeCommon(name: "NewChild"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let opsB = try b.applyLocal(.insertNode(EditOperation.InsertNode(node: newNode, parentID: "parent")))

        // Exchange
        a.applyRemote(opsB)
        b.applyRemote(opsA)

        // parent should be gone on both
        #expect(a.nodes["parent"] == nil)
        #expect(b.nodes["parent"] == nil)

        // Delete-wins semantic: both peers must converge.
        assertConverged(a, b)
    }

    // MARK: - Delete cascades to descendants

    @Test("Delete cascades to all descendants on both peers")
    func deleteCascadesOnBothPeers() throws {
        let grandchild = PenNode(
            id: "grandchild",
            common: PenNodeCommon(name: "Grandchild"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let child = PenNode(
            id: "child",
            common: PenNodeCommon(name: "Child"),
            kind: .frame(PenNode.FrameData(children: [grandchild]))
        )
        let parent = PenNode(
            id: "parent",
            common: PenNodeCommon(name: "Parent"),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        let doc = PenDocument(children: [parent])
        let (a, b) = makePair(from: doc)

        let opsA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "parent")))

        b.applyRemote(opsA)

        #expect(b.nodes["parent"] == nil)
        #expect(b.nodes["child"] == nil)
        #expect(b.nodes["grandchild"] == nil)
        assertConverged(a, b)
    }
}
