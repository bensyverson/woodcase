//
//  DocumentSessionRemoteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A collaborator's CRDT operations through the funnel: what they invalidate, whom the
/// ledger credits, and that they never join the local author's undo or dirty the file.
struct DocumentSessionRemoteTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))
    private let bo = Author(name: "bo", peerID: PeerID(rawValue: "peer-bo"))
    private let file = URL(fileURLWithPath: "/tmp/session-remote.pen")

    private let original = SessionTestDocuments.make().materialize()

    private func makeSession(file: URL? = nil) -> DocumentSession {
        DocumentSession(document: original, author: ana, file: file, collaborative: true)
    }

    private func set(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    // MARK: - Invalidation and the ledger

    @Test("a remote property write names its node and stamps the key under the sender")
    func propertyWriteIsInvalidatedAndStamped() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)

        let change = try session.submit(.remote(peer.edit(set("c1", ["common.name": "Claude"])), from: claude))

        #expect(session.document.nodes["c1"]?.common.name == "Claude")
        #expect(change.origin == .remote)
        #expect(change.author == claude)
        #expect(change.sequence == 1)
        #expect(change.invalidation.nodes == ["c1"])
        #expect(!change.invalidation.structural)
        let stamp = session.ledger.stamp(for: .property(node: "c1", path: "common.name"))
        #expect(stamp == ChangeLedger.Stamp(author: claude, sequence: 1))
    }

    @Test("a remote move names both parents, is structural and stamps the node's place")
    func moveNamesBothParents() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0))

        let change = try session.submit(.remote(peer.edit(move), from: claude))

        #expect(session.document.children["f2"] == ["c2", "c4"])
        #expect(change.invalidation.nodes.isSuperset(of: ["c2", "f1", "f2"]))
        #expect(change.invalidation.structural)
        #expect(session.ledger.stamp(for: .placement(node: "c2"))?.author == claude)
    }

    @Test("a remote insert stamps the existence of every node it creates")
    func insertStampsExistence() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        let child = PenNode(id: "y1", common: PenNodeCommon(name: "Y"), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(id: "x1", common: PenNodeCommon(name: "X"), kind: .frame(PenNode.FrameData(children: [child])))

        let change = try session.submit(.remote(
            peer.edit(.insertNode(EditOperation.InsertNode(node: frame, parentID: "f2"))),
            from: claude
        ))

        #expect(session.document.children["x1"] == ["y1"])
        #expect(change.invalidation.nodes.isSuperset(of: ["x1", "y1", "f2"]))
        #expect(session.ledger.stamp(for: .existence(node: "x1"))?.author == claude)
        #expect(session.ledger.stamp(for: .existence(node: "y1"))?.author == claude)
    }

    @Test("a remote override write stamps each override key it changed")
    func overrideStampsPerKey() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        let override = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "inner", properties: ["opacity": 0.5]
        ))

        try session.submit(.remote(peer.edit(override), from: claude))

        #expect(session.ledger.stamp(for: .override(ref: "ref1", descendant: "inner", key: "opacity"))?.author == claude)
        #expect(session.ledger.stamp(for: .override(ref: "ref1", descendant: "inner", key: "fill")) == nil)
    }

    @Test("a remote variable write invalidates everything and names the variable")
    func variableWriteIsFull() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        let variable = EditOperation.updateVariable(EditOperation.UpdateVariable(
            name: "primary", variable: PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        ))

        let change = try session.submit(.remote(peer.edit(variable), from: claude))

        #expect(change.invalidation.full)
        #expect(change.invalidation.documentLevel.contains(.variable("primary")))
        #expect(session.ledger.stamp(for: .variable(name: "primary"))?.author == claude)
    }

    // MARK: - The peer registry

    @Test("an operation relayed from a peer that joined is credited to that peer's author")
    func relayedOperationIsCreditedToItsPeer() throws {
        let session = makeSession()
        session.noteJoined(bo)
        let peer = SessionTestPeer(bo, document: original)

        let change = try session.submit(.remote(peer.edit(set("c1", ["common.name": "Bo"])), from: claude))

        #expect(change.author == claude)
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))?.author == bo)
    }

    @Test("an operation from a peer nobody introduced is credited to nobody on that peer")
    func unknownPeerIsUnattributed() throws {
        let session = makeSession()
        let peer = SessionTestPeer(bo, document: original)

        try session.submit(.remote(peer.edit(set("c1", ["common.name": "Bo"])), from: claude))

        let stamp = session.ledger.stamp(for: .property(node: "c1", path: "common.name"))
        #expect(stamp?.author == .unattributed(peer: bo.peerID))
    }

    @Test("the sender joins the registry, so its later relays name it")
    func senderJoins() throws {
        let session = makeSession()
        let claudePeer = SessionTestPeer(claude, document: original)
        let claudeOps = try claudePeer.edit(set("c1", ["common.name": "Claude"]))
        try session.submit(.remote(claudeOps, from: claude))

        let later = try claudePeer.edit(set("c2", ["common.name": "Claude"]))
        try session.submit(.remote(later, from: bo))

        #expect(session.ledger.stamp(for: .property(node: "c2", path: "common.name"))?.author == claude)
    }

    @Test("a remote write the CRDT rejects as stale changes and stamps nothing")
    func staleWriteIsIgnored() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        let stale = try peer.edit(set("c1", ["common.name": "Claude"]))
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])])))
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana again"])])))

        let change = try session.submit(.remote(stale, from: claude))

        #expect(session.document.nodes["c1"]?.common.name == "Ana again")
        #expect(change.sequence == 2)
        #expect(change.invalidation.isEmpty)
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))?.author == ana)
    }

    // MARK: - Undo and dirty state

    @Test("remote changes are neither undoable nor dirtying, and write no activity")
    func remoteIsNotUndoableOrDirtying() throws {
        let session = makeSession(file: file)
        let peer = SessionTestPeer(claude, document: original)

        let change = try session.submit(.remote(peer.edit(set("c1", ["common.name": "Claude"])), from: claude))

        #expect(!change.isUndoable)
        #expect(!change.isDirtying)
        #expect(change.activity.isEmpty)
        #expect(change.broadcast.isEmpty)
        #expect(!session.hasUnsyncedChanges)
        #expect(!session.canUndo)
        let undo = try session.submit(.undo)
        #expect(undo.applied.isEmpty)
        #expect(session.document.nodes["c1"]?.common.name == "Claude")
    }

    @Test("a remote write between an edit and its undo is kept and reported")
    func remoteWriteThenUndoKeepsTheirs() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        try peer.receive(session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana", "kind.width": 7])]))))
        try session.submit(.remote(peer.edit(set("c1", ["common.name": "Claude"])), from: claude))

        let undo = try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Claude")
        #expect(try NodePropertyCodec.value(at: "kind.width", of: #require(session.document.nodes["c1"])) == 100)
        #expect(undo.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    @Test("a remote change leaves redo and the open undo group alone")
    func remoteLeavesHistoryAlone() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        try peer.receive(session.submit(.local(LocalEdit(operations: [set("c2", ["common.name": "Ana"])]))))
        try peer.receive(session.submit(.undo))

        try session.submit(.remote(peer.edit(set("c1", ["common.name": "Claude"])), from: claude))

        #expect(session.canRedo)
    }

    @Test("an op from the session's own replica is credited to the session's author, whoever sent it")
    func ownReplicaOpIsCreditedToAuthor() throws {
        let session = makeSession()
        let beforeCrash = SessionTestPeer(ana, document: original)

        let change = try session.submit(.remote(
            beforeCrash.edit(set("c1", ["common.name": "Ana"])),
            from: .unattributed(peer: ana.peerID)
        ))

        #expect(change.author == ana)
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))?.author == ana)
    }

    @Test("a session that is not collaborative refuses remote operations")
    func nonCollaborativeRefuses() throws {
        let session = DocumentSession(document: original, author: ana)
        let peer = SessionTestPeer(claude, document: original)
        let ops = try peer.edit(set("c1", ["common.name": "Claude"]))

        #expect(throws: SessionError.notCollaborative) {
            try session.submit(.remote(ops, from: claude))
        }
        #expect(session.document.nodes["c1"]?.common.name == "Child1")
    }
}
