//
//  DocumentSessionAtomicityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A submission lands whole or not at all, and a checkpoint rolls the session back whole.
struct DocumentSessionAtomicityTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let file = URL(fileURLWithPath: "/tmp/session-atomic.pen")

    private func makeSession(collaborative: Bool = false) -> DocumentSession {
        DocumentSession(
            document: SessionTestDocuments.make().materialize(),
            author: ana,
            file: file,
            collaborative: collaborative
        )
    }

    /// Three operations that apply, then one that names a missing node.
    private var failingPartWay: LocalEdit {
        LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Renamed"])),
            .moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0)),
            .detachRef(EditOperation.DetachRef(refNodeID: "ref1")),
            .deleteNode(EditOperation.DeleteNode(nodeID: "missing")),
        ])
    }

    @Test("a multi-op edit failing part-way leaves document, ledger and events untouched", arguments: [false, true])
    func failingPartWayLeavesNoTrace(collaborative: Bool) throws {
        let session = makeSession(collaborative: collaborative)
        try session.submit(.local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: "c3", properties: ["common.name": "Earlier"])),
        ])))
        let checkpoint = session.checkpoint()
        let document = session.document.materialize()
        let ledger = session.ledger
        let sequence = session.sequence

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try session.submit(.local(failingPartWay))
        }

        #expect(session.document.materialize() == document)
        #expect(session.ledger == ledger)
        #expect(session.sequence == sequence)
        #expect(session.journaledActivity.isEmpty)
        #expect(session.journal?.count == checkpoint.journalCount)
    }

    @Test("a collaborative edit failing part-way leaves the CRDT state untouched")
    func failingPartWayLeavesCRDTUntouched() throws {
        let session = makeSession(collaborative: true)
        let crdt = try #require(session.document.crdtDocument)
        let before = crdt.snapshot()

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try session.submit(.local(failingPartWay))
        }

        #expect(crdt.snapshot() == before)
    }

    @Test("a collaborative edit failing part-way does not diverge from a concurrent peer")
    func failingPartWayConverges() throws {
        let session = makeSession(collaborative: true)
        let peer = EditableDocument(from: SessionTestDocuments.make().materialize(), peerID: PeerID(rawValue: "peer-bo"))
        let theirs = try peer.applyLocal(
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Bo"]))
        )

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try session.submit(.local(failingPartWay))
        }
        session.document.applyRemote(theirs)

        #expect(session.document.nodes["c1"]?.common.name == "Bo")
        #expect(peer.materialize() == session.document.materialize())
    }

    @Test("rollback to a checkpoint reverts the document, the ledger and the journaled events")
    func rollbackRevertsEverything() throws {
        let session = makeSession()
        let document = session.document.materialize()
        let checkpoint = session.checkpoint()
        let ledger = session.ledger

        try session.submit(.local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Renamed"])),
        ])))
        try session.submit(.local(LocalEdit(operations: [
            .moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0)),
            .detachRef(EditOperation.DetachRef(refNodeID: "ref1")),
        ])))
        #expect(session.journaledActivity.count == 3)

        try session.rollback(to: checkpoint)

        #expect(session.document.materialize() == document)
        #expect(session.ledger == ledger)
        #expect(session.journaledActivity.isEmpty)
        #expect(!session.hasUnsyncedChanges)
    }

    @Test("rollback keeps what came before the checkpoint")
    func rollbackKeepsEarlierWork() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Kept"])),
        ])))
        let checkpoint = session.checkpoint()
        let document = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [
            .deleteNode(EditOperation.DeleteNode(nodeID: "f2")),
        ])))

        try session.rollback(to: checkpoint)

        #expect(session.document.materialize() == document)
        #expect(session.document.nodes["c1"]?.common.name == "Kept")
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))?.sequence == 1)
        #expect(session.ledger.stamp(for: .existence(node: "f2")) == nil)
    }

    @Test("sequence numbers are never reused after a rollback")
    func sequenceMonotonic() throws {
        let session = makeSession()
        let checkpoint = session.checkpoint()
        try session.submit(.local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Gone"])),
        ])))
        try session.rollback(to: checkpoint)
        let next = try session.submit(.local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Next"])),
        ])))
        #expect(next.sequence == 2)
    }

    @Test("a collaborative rollback returns the compensating ops a peer converges on")
    func collaborativeRollback() throws {
        let session = makeSession(collaborative: true)
        let peer = EditableDocument(from: SessionTestDocuments.make().materialize(), peerID: PeerID(rawValue: "peer-bo"))
        let checkpoint = session.checkpoint()
        let change = try session.submit(.local(LocalEdit(operations: [
            .moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0)),
        ])))
        peer.applyRemote(change.broadcast)

        let compensating = try session.rollback(to: checkpoint)

        #expect(!compensating.isEmpty)
        peer.applyRemote(compensating)
        #expect(peer.materialize() == session.document.materialize())
    }
}
