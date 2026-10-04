//
//  DocumentSessionSnapshotTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Snapshots are Sendable values for background work; `noteSynced` tracks what is saved.
struct DocumentSessionSnapshotTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))

    private func makeSession() -> DocumentSession {
        DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana, file: nil, collaborative: false)
    }

    private func rename(_ name: String, in session: DocumentSession) throws {
        try session.submit(.local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": AnyCodable(stringLiteral: name)])),
        ])))
    }

    @Test("a snapshot carries the document, sequence and revision, and crosses into a detached task")
    func snapshotIsSendable() async throws {
        let session = makeSession()
        try rename("Renamed", in: session)
        let snapshot = session.snapshot()

        let (name, revision) = await Task.detached {
            let editable = EditableDocument(from: snapshot.document)
            return (editable.nodes["c1"]?.common.name, editable.documentRevision)
        }.value

        #expect(name == "Renamed")
        #expect(snapshot.sequence == 1)
        #expect(snapshot.documentRevision == session.document.documentRevision)
        #expect(revision == snapshot.documentRevision)
    }

    @Test("a snapshot is unaffected by later edits")
    func snapshotIsAValue() throws {
        let session = makeSession()
        let snapshot = session.snapshot()
        try rename("Later", in: session)
        #expect(snapshot.sequence == 0)
        #expect(snapshot.document == SessionTestDocuments.make().materialize())
    }

    @Test("a dirtying change is unsynced until noteSynced covers its sequence")
    func noteSynced() throws {
        let session = makeSession()
        #expect(!session.hasUnsyncedChanges)
        try rename("One", in: session)
        #expect(session.hasUnsyncedChanges)

        let saved = session.snapshot()
        try rename("Two", in: session)
        session.noteSynced(saved.document, through: saved.sequence)
        #expect(session.syncedSequence == 1)
        #expect(session.hasUnsyncedChanges)
        #expect(session.base?.materialize() == saved.document)

        session.noteSynced(session.document.materialize(), through: session.sequence)
        #expect(!session.hasUnsyncedChanges)
    }
}
