//
//  DocumentSessionMakeCollaborativeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A session that starts sharing gains a CRDT in place: the session and everything it
/// remembers stay, so undo still undoes what its author did.
struct DocumentSessionMakeCollaborativeTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let bo = Author(name: "bo", peerID: PeerID(rawValue: "peer-bo"))

    private func rename(_ nodeID: String, to name: String) -> SessionOrigin {
        .local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": AnyCodable(stringLiteral: name)])),
        ]))
    }

    private func makeEditedSession() throws -> DocumentSession {
        let session = DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana)
        try session.submit(rename("c1", to: "Renamed"))
        return session
    }

    @Test("a session made collaborative keeps its undo history and sequence, under its author's peer id")
    func keepsHistory() throws {
        let session = try makeEditedSession()

        session.makeCollaborative()

        #expect(session.document.crdtDocument?.peerID == ana.peerID)
        #expect(session.canUndo)
        #expect(session.sequence == 1)
        #expect(session.document.nodes["c1"]?.common.name == "Renamed")
    }

    @Test("undoing an edit made before sharing broadcasts operations a joiner accepts")
    func undoBroadcastsToJoiner() throws {
        let session = try makeEditedSession()
        session.makeCollaborative()
        let joiner = try DocumentSession(joining: #require(session.document.stateTransfer()), author: bo)

        let undo = try session.submit(.undo)

        #expect(!undo.broadcast.isEmpty)
        try joiner.submit(.remote(undo.broadcast, from: ana))
        #expect(joiner.document.nodes["c1"]?.common.name == "Child1")
        #expect(joiner.document.materialize() == session.document.materialize())
    }

    @Test("making a collaborative session collaborative again keeps its CRDT")
    func idempotent() throws {
        let session = DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana, collaborative: true)
        try session.submit(rename("c1", to: "Renamed"))
        let fingerprint = session.document.seedFingerprint

        session.makeCollaborative()

        #expect(session.document.seedFingerprint == fingerprint)
        #expect(session.document.crdtDocument?.operationLog.operations.isEmpty == false)
    }
}
