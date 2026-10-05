//
//  RemoteApplyScopeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A collaborator's change costs what it touched, not the document.
///
/// A remote batch leaves every cached revision off the spines it touched in place, so the
/// next read — a session commit's own ``EditableDocument/documentRevision`` among them —
/// rehashes only those spines. The caches are read straight after the batch, before
/// anything could warm them again, and the session's answers are checked against a
/// document built from scratch.
@MainActor
struct RemoteApplyScopeTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))

    /// Two boards of two cards each.
    private let board = PenDocument(children: ["A", "B"].map { board in
        PenNode(id: board, common: PenNodeCommon(name: board), kind: .frame(PenNode.FrameData(children: [1, 2].map { card in
            PenNode(
                id: "\(board)\(card)",
                common: PenNodeCommon(name: "\(board)\(card)"),
                kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
            )
        })))
    })

    /// A collaborative replica of the boards with every revision cached.
    private func warmReplica() -> EditableDocument {
        let replica = EditableDocument(from: board, peerID: PeerID(rawValue: "peer-ana"))
        for nodeID in replica.nodes.keys {
            _ = replica.revision(of: nodeID)
        }
        return replica
    }

    @Test("a remote property write forgets its spine and keeps every other revision")
    func propertyWriteKeepsOtherRevisions() throws {
        let replica = warmReplica()
        let peer = SessionTestPeer(claude, document: board)

        try replica.applyRemote(peer.edit(.setProperties(EditOperation.SetProperties(nodeID: "A1", properties: ["kind.fills": .string("#FF0000")]))))

        let cached = try #require(replica.revisionCache).entries
        for forgotten in ["A", "A1"] {
            #expect(cached[forgotten] == nil, "\(forgotten) is still cached")
        }
        for kept in ["A2", "B", "B1", "B2"] {
            #expect(cached[kept] != nil, "\(kept) was forgotten")
        }
    }

    @Test("a remote move forgets both spines and keeps every other revision")
    func moveKeepsOtherRevisions() throws {
        let replica = warmReplica()
        let peer = SessionTestPeer(claude, document: board)

        try replica.applyRemote(peer.edit(.moveNode(EditOperation.MoveNode(nodeID: "A1", newParentID: "B"))))

        let cached = try #require(replica.revisionCache).entries
        for forgotten in ["A", "A1", "B"] {
            #expect(cached[forgotten] == nil, "\(forgotten) is still cached")
        }
        for kept in ["A2", "B1", "B2"] {
            #expect(cached[kept] != nil, "\(kept) was forgotten")
        }
        #expect(replica.children == EditableDocument(from: replica.materialize()).children)
    }

    @Test("a session's remote changes report the revisions a from-scratch document computes")
    func sessionRevisionsMatchScratch() throws {
        let session = DocumentSession(document: board, author: ana, collaborative: true)
        let peer = SessionTestPeer(claude, document: board)
        for operation: EditOperation in [
            .setProperties(EditOperation.SetProperties(nodeID: "A1", properties: ["kind.fills": .string("#FF0000")])),
            .moveNode(EditOperation.MoveNode(nodeID: "A1", newParentID: "B", index: 0)),
            .deleteNode(EditOperation.DeleteNode(nodeID: "B2")),
        ] {
            let change = try session.submit(.remote(peer.edit(operation), from: claude))

            let scratch = EditableDocument(from: session.document.materialize())
            #expect(change.documentRevision == scratch.documentRevision)
            for nodeID in session.document.nodes.keys {
                #expect(session.document.revision(of: nodeID) == scratch.revision(of: nodeID))
            }
        }
        #expect(session.document.children["B"] == ["A1", "B1"])
    }
}
