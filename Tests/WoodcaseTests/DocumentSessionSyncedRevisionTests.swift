//
//  DocumentSessionSyncedRevisionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A session knows the revision of what its file holds, so a save can check the file
/// still holds it.
struct DocumentSessionSyncedRevisionTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))

    private static func rename(_ nodeID: String, to name: String) -> SessionOrigin {
        .local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": .string(name)])),
        ]))
    }

    @Test("a new session's synced revision is the revision of the document it opened")
    func openedRevision() throws {
        let opened = SessionTestDocuments.make()
        let session = DocumentSession(document: opened.materialize(), author: ana)
        try session.submit(Self.rename("c1", to: "Edited"))

        #expect(session.syncedRevision == opened.documentRevision)
        #expect(session.snapshot().syncedRevision == opened.documentRevision)
    }

    @Test("noting a saved snapshot makes its revision the synced one, without building a base")
    func noteSyncedSnapshot() throws {
        let session = DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana)
        try session.submit(Self.rename("c1", to: "Saved"))
        let snapshot = session.snapshot()
        try session.submit(Self.rename("c1", to: "Later"))

        session.noteSynced(snapshot)

        #expect(session.syncedRevision == snapshot.documentRevision)
        #expect(!session.hasBuiltBase)
        #expect(session.syncedSequence == snapshot.sequence)
        #expect(session.hasUnsyncedChanges)
        #expect(session.base?.materialize() == snapshot.document)
    }

    @Test("a file merge makes the file's revision the synced one")
    func mergeMovesSyncedRevision() throws {
        let session = DocumentSession(
            document: SessionTestDocuments.make().materialize(), author: ana, merger: .threeWay
        )
        let theirs = SessionTestDocuments.make()
        try theirs.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "c2", properties: ["common.name": "Theirs"]
        )))

        try session.submit(.file(theirs.materialize(), author: claude))

        #expect(session.syncedRevision == theirs.documentRevision)
    }

    @Test("a wrapping session with no file state has no synced revision")
    func unknownHasNone() {
        let session = DocumentSession(editing: SessionTestDocuments.make(), author: ana, file: nil)
        #expect(session.syncedRevision == nil)
        #expect(session.snapshot().syncedRevision == nil)
    }
}
