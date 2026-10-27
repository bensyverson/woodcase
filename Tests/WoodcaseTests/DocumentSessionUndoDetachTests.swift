//
//  DocumentSessionUndoDetachTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A session's undo and redo of a detach that rewrote connector ends: the reversal's
/// connector restores are guarded by keys naming the ref the same reversal puts back,
/// so its guards have to be weighed in step order (leaf DbitT1).
struct DocumentSessionUndoDetachTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))

    private func makeSession(collaborative: Bool) throws -> DocumentSession {
        try DocumentSession(document: NestedDetachFixture.parsed(), author: ana, collaborative: collaborative)
    }

    /// Commits an edit, then undoes, redoes and undoes it again, checking the document
    /// against the state before and after the edit at every step.
    private func roundTrip(_ operation: EditOperation, collaborative: Bool) throws {
        let session = try makeSession(collaborative: collaborative)
        let before = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [operation])))
        let after = session.document.materialize()
        #expect(after != before)

        let undo = try session.submit(.undo)
        #expect(!undo.applied.isEmpty)
        #expect(session.document.materialize() == before)

        let redo = try session.submit(.redo)
        #expect(!redo.applied.isEmpty)
        #expect(session.document.materialize() == after)

        try session.submit(.undo)
        #expect(session.document.materialize() == before)
    }

    @Test("undo and redo of a detach that rewrote connector ends restore the document exactly", arguments: [false, true])
    func detachRoundTrip(collaborative: Bool) throws {
        try roundTrip(.detachRef(EditOperation.DetachRef(refNodeID: "ok")), collaborative: collaborative)
    }

    @Test("undo and redo of a deleting detach that rewrote connector ends restore the document exactly", arguments: [false, true])
    func deletingDetachRoundTrip(collaborative: Bool) throws {
        try roundTrip(
            .deleteNode(EditOperation.DeleteNode(nodeID: "Kit", instances: .detach)),
            collaborative: collaborative
        )
    }

    @Test("an undo stopped by a node nobody else removed reports it rather than doing nothing silently")
    func uncreditedRefusalIsReported() throws {
        let session = DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana)
        try session.submit(.local(LocalEdit(operations: [.deleteNode(EditOperation.DeleteNode(nodeID: "c4"))])))
        try session.submit(.local(LocalEdit(
            operations: [.deleteNode(EditOperation.DeleteNode(nodeID: "f2"))],
            undoGroup: .none
        )))

        let undo = try session.submit(.undo)

        #expect(undo.applied.isEmpty)
        #expect(undo.kept.isEmpty)
        #expect(undo.unrestored == [.existence(node: "f2")])
        #expect(undo.undoEffect == .consumedEntry)
    }
}
