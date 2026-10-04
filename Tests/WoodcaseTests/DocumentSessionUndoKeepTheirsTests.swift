//
//  DocumentSessionUndoKeepTheirsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Undo is per author and keeps everyone else's later work, reporting what it kept.
///
/// Every other author's write arrives the way it does in the app: made on their own
/// replica, delivered as ``SessionOrigin/remote(_:from:)`` to a collaborative session.
struct DocumentSessionUndoKeepTheirsTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))

    /// Ana's collaborative session and one collaborator's replica, kept in step: every
    /// change Ana's session broadcasts reaches the replica before the collaborator edits.
    private final class Collaboration {
        init(ana: Author, other: Author) {
            let original = SessionTestDocuments.make().materialize()
            session = DocumentSession(document: original, author: ana, collaborative: true)
            peer = SessionTestPeer(other, document: original)
        }

        let session: DocumentSession
        let peer: SessionTestPeer

        /// Submits something of Ana's and hands its broadcast to the collaborator.
        @discardableResult
        func mine(_ origin: SessionOrigin) throws -> CommittedChange {
            let change = try session.submit(origin)
            peer.receive(change)
            return change
        }

        /// The collaborator edits, and Ana's session receives it.
        func theirs(_ operation: EditOperation) throws {
            try session.submit(.remote(peer.edit(operation), from: peer.author))
        }
    }

    private func set(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    private func edit(_ operations: EditOperation..., group: UndoGroup = .new) -> SessionOrigin {
        .local(LocalEdit(operations: operations, undoGroup: group))
    }

    // MARK: - Property and override keys

    @Test("undo after another author's later write to the same key keeps their value and reports it")
    func laterForeignWriteIsKept() throws {
        let team = Collaboration(ana: ana, other: claude)
        try team.mine(edit(set("c1", ["common.name": "Ana"])))
        try team.theirs(set("c1", ["common.name": "Claude"]))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["c1"]?.common.name == "Claude")
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    @Test("only the contested key is kept; the author's other keys are undone")
    func uncontestedKeysAreUndone() throws {
        let team = Collaboration(ana: ana, other: claude)
        try team.mine(edit(set("c1", ["common.name": "Ana", "kind.width": 7])))
        try team.theirs(set("c1", ["kind.width": 9]))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["c1"]?.common.name == "Child1")
        #expect(try NodePropertyCodec.value(at: "kind.width", of: #require(team.session.document.nodes["c1"])) == 9)
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "kind.width"), author: claude)])
    }

    @Test("a foreign write older than the author's edit is overwritten as usual")
    func earlierForeignWriteIsUndone() throws {
        let team = Collaboration(ana: ana, other: claude)
        try team.theirs(set("c1", ["common.name": "Claude"]))
        try team.mine(edit(set("c1", ["common.name": "Ana"])))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["c1"]?.common.name == "Claude")
        #expect(change.kept.isEmpty)
    }

    @Test("the same person in another window is another author")
    func otherReplicaIsForeign() throws {
        let anaElsewhere = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana-2"))
        let team = Collaboration(ana: ana, other: anaElsewhere)
        try team.mine(edit(set("c1", ["common.name": "Ana"])))
        try team.theirs(set("c1", ["common.name": "Other window"]))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["c1"]?.common.name == "Other window")
        #expect(change.kept.map(\.author) == [anaElsewhere])
    }

    @Test("an override key another author wrote later is kept")
    func overrideKeyIsKept() throws {
        let team = Collaboration(ana: ana, other: claude)
        let mine = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#00ff00", "opacity": 0.5]
        ))
        let theirs = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#0000ff"]
        ))
        try team.mine(edit(mine))
        try team.theirs(theirs)

        let change = try team.mine(.undo)

        guard case let .ref(data) = team.session.document.nodes["ref1"]?.kind else {
            Issue.record("ref1 is no longer a ref")
            return
        }
        #expect(data.descendants?["inner"]?.properties == ["fill": "#0000ff"])
        #expect(change.kept == [KeptChange(key: .override(ref: "ref1", descendant: "inner", key: "fill"), author: claude)])
    }

    @Test("a coalesced group keeps a foreign write made part-way through it")
    func coalescedGroupKeepsMidGroupWrite() throws {
        let team = Collaboration(ana: ana, other: claude)
        try team.mine(edit(set("c1", ["common.name": "Ana"]), group: .coalesce("g")))
        try team.theirs(set("c1", ["common.name": "Claude"]))
        try team.mine(edit(set("c2", ["common.name": "Ana"]), group: .coalesce("g")))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["c1"]?.common.name == "Claude")
        #expect(team.session.document.nodes["c2"]?.common.name == "Child2")
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    @Test("a redo keeps another author's write made after the undo")
    func redoKeepsTheirs() throws {
        let team = Collaboration(ana: ana, other: claude)
        try team.mine(edit(set("c1", ["common.name": "Ana"])))
        try team.mine(.undo)
        try team.theirs(set("c1", ["common.name": "Claude"]))

        let change = try team.mine(.redo)

        #expect(team.session.document.nodes["c1"]?.common.name == "Claude")
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    // MARK: - Structural steps

    @Test("undoing an insert after a foreign edit inside it keeps the node and reports the edit")
    func insertWithForeignEditInsideIsKept() throws {
        let team = Collaboration(ana: ana, other: claude)
        let child = PenNode(id: "y1", common: PenNodeCommon(name: "Y"), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(id: "x1", common: PenNodeCommon(name: "X"), kind: .frame(PenNode.FrameData(children: [child])))
        try team.mine(edit(.insertNode(EditOperation.InsertNode(node: frame, parentID: "f2"))))
        try team.theirs(set("y1", ["common.name": "Claude's"]))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["x1"] != nil)
        #expect(team.session.document.nodes["y1"]?.common.name == "Claude's")
        #expect(change.kept == [KeptChange(key: .property(node: "y1", path: "common.name"), author: claude)])
    }

    @Test("undoing an insert after another author put a node inside it keeps both")
    func insertWithForeignChildIsKept() throws {
        let team = Collaboration(ana: ana, other: claude)
        let frame = PenNode(id: "x1", common: PenNodeCommon(name: "X"), kind: .frame(PenNode.FrameData()))
        let theirs = PenNode(id: "z1", common: PenNodeCommon(name: "Z"), kind: .rectangle(PenNode.RectangleData()))
        try team.mine(edit(.insertNode(EditOperation.InsertNode(node: frame, parentID: "f2"))))
        try team.theirs(.insertNode(EditOperation.InsertNode(node: theirs, parentID: "x1")))

        let change = try team.mine(.undo)

        #expect(team.session.document.children["x1"] == ["z1"])
        #expect(Set(change.kept.map(\.key)) == [.existence(node: "z1"), .placement(node: "z1")])
        #expect(change.kept.allSatisfy { $0.author == claude })
    }

    @Test("undoing an insert nobody else touched removes it")
    func untouchedInsertIsUndone() throws {
        let team = Collaboration(ana: ana, other: claude)
        let frame = PenNode(id: "x1", common: PenNodeCommon(name: "X"), kind: .frame(PenNode.FrameData()))
        try team.mine(edit(.insertNode(EditOperation.InsertNode(node: frame, parentID: "f2"))))
        try team.theirs(set("c1", ["common.name": "Elsewhere"]))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["x1"] == nil)
        #expect(change.kept.isEmpty)
    }

    @Test("undoing a detach after a foreign edit inside the expansion keeps it and leaves the instance detached")
    func detachWithForeignEditInsideIsKept() throws {
        let team = Collaboration(ana: ana, other: claude)
        let detach = try team.mine(edit(.detachRef(EditOperation.DetachRef(refNodeID: "ref1"))))
        guard case let .deleteNode(delete)? = detach.applied.first?.inverse.first?.operation else {
            Issue.record("a detach's inverse starts by deleting the expansion")
            return
        }
        let expandedChild = try #require(team.session.document.children[delete.nodeID]?.first)
        try team.theirs(set(expandedChild, ["common.name": "Claude's"]))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes[delete.nodeID] != nil)
        #expect(team.session.document.nodes["ref1"] == nil)
        #expect(change.kept == [KeptChange(key: .property(node: expandedChild, path: "common.name"), author: claude)])
    }

    @Test("undoing a move another author has since moved again keeps their placement")
    func moveMovedAgainIsKept() throws {
        let team = Collaboration(ana: ana, other: claude)
        try team.mine(edit(.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0))))
        try team.theirs(.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f1", index: 0)))

        let change = try team.mine(.undo)

        #expect(team.session.document.children["f1"] == ["c2", "c1", "c3"])
        #expect(change.kept == [KeptChange(key: .placement(node: "c2"), author: claude)])
    }

    @Test("undoing a delete whose parent another author has since deleted keeps their delete")
    func deleteWithParentGoneIsKept() throws {
        let team = Collaboration(ana: ana, other: claude)
        try team.mine(edit(.deleteNode(EditOperation.DeleteNode(nodeID: "c4"))))
        try team.theirs(.deleteNode(EditOperation.DeleteNode(nodeID: "f2")))

        let change = try team.mine(.undo)

        #expect(team.session.document.nodes["c4"] == nil)
        #expect(team.session.document.nodes["f2"] == nil)
        #expect(change.kept == [KeptChange(key: .existence(node: "f2"), author: claude)])
    }
}
