//
//  FlatStoreJournalTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The journal keeps each entry as it was before the change first wrote it, and knows
/// when a change placed nothing.
@MainActor
struct FlatStoreJournalTests {
    /// A frame holding two rectangles.
    private let document = PenDocument(children: [
        PenNode(id: "F", common: PenNodeCommon(name: "F"), kind: .frame(PenNode.FrameData(children: ["a", "b"].map {
            PenNode(id: $0, common: PenNodeCommon(name: $0), kind: .rectangle(PenNode.RectangleData()))
        }))),
    ])

    @Test("the first note of an entry wins")
    func firstNoteWins() {
        let editable = EditableDocument(from: document)
        var journal = FlatStoreJournal()
        journal.noteNode("a", in: editable)
        journal.noteChildren(of: "F", in: editable)
        editable.children["F"] = ["b"]
        editable.nodes["a"]?.common.name = "renamed"
        journal.noteNode("a", in: editable)
        journal.noteChildren(of: "F", in: editable)

        #expect(journal.nodes["a"]??.common.name == "a")
        #expect(journal.children["F"] == .some(["a", "b"]))
    }

    @Test("a node the change creates is noted as absent, and the root order under nil")
    func absenceAndRoot() {
        let editable = EditableDocument(from: document)
        var journal = FlatStoreJournal()
        journal.noteNode("new", in: editable)
        journal.noteChildren(of: nil, in: editable)

        #expect(journal.nodes.keys.contains("new"))
        #expect(journal.nodes["new"] == .some(nil))
        #expect(journal.rootOrder == ["F"])
    }

    @Test("a change that wrote only content moves nothing; one that created a node does")
    func movesNothing() {
        let editable = EditableDocument(from: document)
        var content = FlatStoreJournal()
        content.noteNode("a", in: editable)
        #expect(content.movesNothing(in: editable))

        var creation = FlatStoreJournal()
        creation.noteNode("c", in: editable)
        editable.nodes["c"] = PenNode(id: "c", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        #expect(!creation.movesNothing(in: editable))
    }

    @Test("a local move notes the node's parent and both lists")
    func moveFootprint() {
        let editable = EditableDocument(from: document)
        var journal = FlatStoreJournal()
        journal.noteFootprint(of: .moveNode(EditOperation.MoveNode(nodeID: "a", newParentID: nil)), in: editable)

        #expect(journal.parents["a"] == .some("F"))
        #expect(journal.children.keys.contains("F"))
        #expect(journal.rootOrder == ["F"])
    }

    @Test("a local edit the CRDT places elsewhere marks the store, and the next batch settles it whole")
    func unsettledStoreReconcilesWhole() throws {
        let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
        let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))
        let base = SessionTestDocuments.make().materialize()
        let session = DocumentSession(document: base, author: ana, collaborative: true)
        let peer = SessionTestPeer(claude, document: base)
        // Concurrent moves that would close a cycle: the tree keeps ana's, so claude's
        // leaves f2 a live entry at the head of f1's list, where the flat store has none —
        // and an insert at index 1 of f1 lands, in the lists, before c1.
        let crossing = try peer.edit(.moveNode(EditOperation.MoveNode(nodeID: "f2", newParentID: "f1", index: 0)))
        try session.submit(.local(LocalEdit(operations: [.moveNode(EditOperation.MoveNode(nodeID: "f1", newParentID: "f2"))])))
        try session.submit(.remote(crossing, from: claude))
        #expect(session.document.parents["f1"] == "f2")
        let node = PenNode(id: "n1", common: PenNodeCommon(name: "New"), kind: .rectangle(PenNode.RectangleData()))
        try session.submit(.local(LocalEdit(operations: [.insertNode(EditOperation.InsertNode(node: node, parentID: "f1", index: 1))])))
        #expect(session.document._placementUnsettled)

        try session.submit(.remote(peer.edit(.setProperties(EditOperation.SetProperties(
            nodeID: "c1", properties: ["common.name": .string("Claude")]
        ))), from: claude))

        #expect(!session.document._placementUnsettled)
        let settled = (session.document.parents, session.document.children, session.document.rootOrder)
        session.document.reconcileChildrenWithParents()
        #expect(session.document.parents == settled.0)
        #expect(session.document.children == settled.1)
        #expect(session.document.rootOrder == settled.2)
    }
}
