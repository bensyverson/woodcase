//
//  SessionDeepKeyCollaborationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A deep metadata key written through a session merges with other authors' work on
/// sibling entries — concurrently, and across an undo — and its activity rows replay
/// exactly.
struct SessionDeepKeyCollaborationTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))
    private let file = URL(fileURLWithPath: "/tmp/session-deep-keys.pen")
    private let original: [String: AnyCodable] = ["type": "design", "woodcase": ["tint": "#FFF59D"]]

    private func set(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    private func local(_ operations: EditOperation...) -> SessionOrigin {
        .local(LocalEdit(operations: operations))
    }

    private func metadata(_ nodeID: String, in session: DocumentSession) -> [String: AnyCodable]? {
        session.document.nodes[nodeID]?.common.metadata?.object
    }

    /// Ana's collaborative session over `c2` with ``original`` metadata, and Claude's replica.
    private func collaboration() throws -> (DocumentSession, SessionTestPeer) {
        let session = try SessionDeepKeyTests.session(author: ana, c2: original, collaborative: true)
        let peer = SessionTestPeer(claude, document: session.document.materialize())
        return (session, peer)
    }

    // MARK: - Collaboration

    @Test("a deep-key write and a collaborator's concurrent write to a sibling entry both survive")
    func concurrentSiblingWritesMerge() throws {
        let (session, peer) = try collaboration()
        let theirs = try peer.edit(set("c2", ["common.metadata": ["type": "design", "woodcase": ["tint": "#A5D6A7"]]]))

        let mine = try session.submit(local(set("c2", ["common.metadata.woodcase.spans": SessionDeepKeyTests.spans])))
        try session.submit(.remote(theirs, from: claude))
        peer.receive(mine)

        let expected: [String: AnyCodable] = [
            "type": "design", "woodcase": ["tint": "#A5D6A7", "spans": SessionDeepKeyTests.spans],
        ]
        #expect(metadata("c2", in: session) == expected)
        #expect(peer.replica.nodes["c2"]?.common.metadata?.object == expected)
    }

    @Test("undo of a deep-key write keeps a collaborator's later write to a sibling entry")
    func undoKeepsSiblingEntry() throws {
        let (session, peer) = try collaboration()
        try peer.receive(session.submit(local(set("c2", ["common.metadata.woodcase.spans": SessionDeepKeyTests.spans]))))
        let theirs = try peer.edit(set("c2", ["common.metadata": [
            "type": "design", "woodcase": ["tint": "#A5D6A7", "spans": SessionDeepKeyTests.spans],
        ]]))
        try session.submit(.remote(theirs, from: claude))

        let undo = try session.submit(.undo)

        #expect(metadata("c2", in: session) == ["type": "design", "woodcase": ["tint": "#A5D6A7"]])
        #expect(undo.kept.isEmpty)
    }

    @Test("undo of a deep-key write keeps a collaborator's later write to the same entry and reports it")
    func undoKeepsSameEntry() throws {
        let (session, peer) = try collaboration()
        try peer.receive(session.submit(local(set("c2", ["common.metadata.woodcase.spans": SessionDeepKeyTests.spans]))))
        let replaced: AnyCodable = ["text": "yo", "runs": []]
        let theirs = try peer.edit(set("c2", ["common.metadata": [
            "type": "design", "woodcase": ["tint": "#FFF59D", "spans": replaced],
        ]]))
        try session.submit(.remote(theirs, from: claude))

        let undo = try session.submit(.undo)

        #expect(metadata("c2", in: session) == ["type": "design", "woodcase": ["tint": "#FFF59D", "spans": replaced]])
        #expect(undo.kept == [KeptChange(key: .property(node: "c2", path: "common.metadata.woodcase.spans"), author: claude)])
    }

    // MARK: - Activity

    @Test("a deep-key write's activity row records the edit as submitted and an inverse that replays exactly")
    func activityInverseReplaysExactly() throws {
        let before: [String: AnyCodable] = ["type": "design", "_role": "button"]
        let session = try SessionDeepKeyTests.session(author: ana, c1: before, file: file)
        let submitted = set("c1", ["common.metadata.woodcase.role": "link"])

        let change = try session.submit(local(submitted))
        let row = try #require(change.activity.first)

        #expect(row.forward == [submitted])
        try session.submit(.local(LocalEdit(operations: row.inverse)))
        #expect(metadata("c1", in: session) == before)
    }

    @Test("a folded run of deep-key writes keeps one write each way, and both replay exactly")
    func foldedRunReplaysExactly() throws {
        let session = try SessionDeepKeyTests.session(author: ana, c2: original, file: file)
        let first: AnyCodable = ["text": "h", "runs": []]
        let changes = try [
            session.submit(local(set("c2", ["common.metadata.woodcase.spans": first]))),
            session.submit(local(set("c2", ["common.metadata.woodcase.spans": SessionDeepKeyTests.spans]))),
        ]
        let end = metadata("c2", in: session)

        let row = try #require(CommittedChange.folding(changes)?.activity.first)

        #expect(row.forward.count == 1)
        #expect(row.inverse.count == 1)
        try session.submit(.local(LocalEdit(operations: row.inverse)))
        #expect(metadata("c2", in: session) == original)
        try session.submit(.local(LocalEdit(operations: row.forward)))
        #expect(metadata("c2", in: session) == end)
    }
}
