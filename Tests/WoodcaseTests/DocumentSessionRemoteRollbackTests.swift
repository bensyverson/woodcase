//
//  DocumentSessionRemoteRollbackTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Ruling 5: a rollback refuses to cross a remote change, and a remote change leaves
/// the open coalescing group open.
struct DocumentSessionRemoteRollbackTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))
    private let original = SessionTestDocuments.make().materialize()

    private func makeSession() -> DocumentSession {
        DocumentSession(
            document: original, author: ana, file: URL(fileURLWithPath: "/tmp/remote-rollback.pen"), collaborative: true
        )
    }

    private func set(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    @Test("a rollback across a journaled remote change refuses and leaves the session as it was")
    func rollbackAcrossRemoteRefuses() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        let checkpoint = session.checkpoint()
        try peer.receive(session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])]))))
        try session.submit(.remote(peer.edit(set("c2", ["common.name": "Claude"])), from: claude))
        let document = session.document.materialize()
        let ledger = session.ledger

        #expect(throws: SessionError.rollbackAcrossRemoteChange) {
            try session.rollback(to: checkpoint)
        }

        #expect(session.document.materialize() == document)
        #expect(session.ledger == ledger)
        #expect(session.journaledActivity.count == 1)
    }

    @Test("a rollback to a checkpoint taken after a remote change still succeeds")
    func rollbackAfterRemoteSucceeds() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        try session.submit(.remote(peer.edit(set("c2", ["common.name": "Claude"])), from: claude))
        let checkpoint = session.checkpoint()
        let document = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])])))

        try session.rollback(to: checkpoint)

        #expect(session.document.materialize() == document)
    }

    @Test("a remote change does not close the open coalescing group")
    func remoteKeepsCoalescingGroupOpen() throws {
        let session = makeSession()
        let peer = SessionTestPeer(claude, document: original)
        try peer.receive(session.submit(.local(LocalEdit(
            operations: [set("c1", ["kind.width": 10])], undoGroup: .coalesce("drag")
        ))))
        try session.submit(.remote(peer.edit(set("c2", ["common.name": "Claude"])), from: claude))
        try peer.receive(session.submit(.local(LocalEdit(
            operations: [set("c1", ["kind.width": 20])], undoGroup: .coalesce("drag")
        ))))

        try session.submit(.undo)

        #expect(try NodePropertyCodec.value(at: "kind.width", of: #require(session.document.nodes["c1"])) == 100)
        #expect(session.document.nodes["c2"]?.common.name == "Claude")
        #expect(!session.canUndo)
    }
}
