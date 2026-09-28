//
//  CRDTSnapshotTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTSnapshotTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")
    private let peerC = PeerID(rawValue: "ccc")

    private func makeDoc() -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let text = PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData(content: .literal("Hello")))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect, text]))
        )
        return PenDocument(children: [frame])
    }

    // MARK: - Snapshot serialization

    @Test("Snapshot round-trips through JSON")
    func snapshotRoundTripsJSON() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        // Make some edits so the snapshot has meaningful state
        _ = try editable.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Renamed Rect"))
        ))

        let snapshot = try #require(editable.crdtDocument?.snapshot())

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(CRDTSnapshot.self, from: data)

        #expect(decoded.peerID == peerA)
        #expect(decoded.operationLog.operations.count == snapshot.operationLog.operations.count)
        #expect(decoded.tombstones == snapshot.tombstones)
        #expect(decoded.propertyMaps.keys.sorted() == snapshot.propertyMaps.keys.sorted())
        #expect(decoded.childrenLists.keys.sorted() == snapshot.childrenLists.keys.sorted())
    }

    // MARK: - Snapshot captures all state

    @Test("Snapshot captures all state after edits")
    func snapshotCapturesAllState() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        // Update a property
        _ = try editable.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Updated"))
        ))
        // Delete a node
        _ = try editable.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "t1")))

        let snapshot = try #require(editable.crdtDocument?.snapshot())

        // Operation log has ops
        #expect(!snapshot.operationLog.operations.isEmpty)
        // Property maps exist for nodes
        #expect(snapshot.propertyMaps["r1"] != nil)
        // Children lists exist
        #expect(snapshot.childrenLists[CRDTDocument.rootListID] != nil)
        // Tombstones captured
        #expect(snapshot.tombstones.contains("t1"))
        // Tree move state captured
        #expect(snapshot.treeMove.parentMap["r1"] != nil)
    }

    // MARK: - Init from snapshot

    @Test("Init from snapshot produces equivalent CRDT state")
    func initFromSnapshotEquivalent() throws {
        let editableA = EditableDocument(from: makeDoc(), peerID: peerA)

        // Make edits on A
        _ = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Edited"))
        ))

        let snapshot = try #require(editableA.crdtDocument?.snapshot())

        // Create doc B from the snapshot
        let crdtB = CRDTDocument(from: snapshot, peerID: peerB)

        // B should have the same state as A
        #expect(crdtB.propertyMaps.keys.sorted() == editableA.crdtDocument!.propertyMaps.keys.sorted())
        #expect(crdtB.tombstones == editableA.crdtDocument!.tombstones)
        #expect(crdtB.childrenLists.keys.sorted() == editableA.crdtDocument!.childrenLists.keys.sorted())
        // But B has its own peer ID
        #expect(crdtB.peerID == peerB)
    }

    // MARK: - Hot swap end-to-end

    @Test("Hot Swap: peer B joins from A's snapshot, both converge")
    func hotSwapEndToEnd() throws {
        let doc = makeDoc()

        // Peer A starts editing
        let editableA = EditableDocument(from: doc, peerID: peerA)
        let opsA = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "A's Edit"))
        ))

        // Peer B joins from A's snapshot + original .pen
        let snapshot = try #require(editableA.crdtDocument?.snapshot())
        let editableB = EditableDocument(from: doc, snapshot: snapshot, peerID: peerB)

        // Both apply the same subsequent edit from peer A
        let moreOpsA = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "A's Second Edit", opacity: .literal(0.5)))
        ))
        for op in moreOpsA {
            editableB.applyRemote(op)
        }

        // Both should converge
        #expect(editableA.nodes["r1"]?.common.name == editableB.nodes["r1"]?.common.name)
    }

    // MARK: - Offline replay

    @Test("Offline replay merges correctly")
    func offlineReplay() throws {
        let doc = makeDoc()

        // Peer A edits
        let editableA = EditableDocument(from: doc, peerID: peerA)
        _ = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "A's Edit"))
        ))

        // Peer B was offline, made their own edits against the original doc
        let editableB_offline = EditableDocument(from: doc, peerID: peerB)
        let offlineOps = try editableB_offline.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "t1", common: PenNodeCommon(name: "B's Offline Edit"))
        ))

        // Now B joins from A's snapshot + A's current materialized document
        let snapshot = try #require(editableA.crdtDocument?.snapshot())
        let currentDoc = editableA.materialize()
        let editableB = EditableDocument(from: currentDoc, snapshot: snapshot, peerID: peerB)

        // B should already have A's edits from the materialized doc
        #expect(editableB.nodes["r1"]?.common.name == "A's Edit")

        // Replay B's offline ops
        editableB.replayOfflineOperations(offlineOps)

        // B should now have both A's and B's edits
        #expect(editableB.nodes["r1"]?.common.name == "A's Edit")
        #expect(editableB.nodes["t1"]?.common.name == "B's Offline Edit")

        // Send B's offline ops to A
        for op in offlineOps {
            editableA.applyRemote(op)
        }

        // A should also converge
        #expect(editableA.nodes["t1"]?.common.name == "B's Offline Edit")
    }

    // MARK: - Sendable

    @Test("Snapshot is Sendable")
    func snapshotIsSendable() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        let snapshot = try #require(editable.crdtDocument?.snapshot())

        // Pass to nonisolated function — compile-time check
        acceptSendable(snapshot)
    }

    // MARK: - Field parity

    @Test("CRDTSnapshot covers all CRDTDocument stored properties")
    func snapshotFieldParity() throws {
        // This test guards against drift: if a new stored property is added to
        // CRDTDocument but not to CRDTSnapshot/snapshot()/init(from:peerID:),
        // the Mirror-based check below will catch it.
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        let crdt = try #require(editable.crdtDocument)
        let snapshot = crdt.snapshot()

        // CRDTDocument stored properties (excluding peerID, which is intentionally
        // different between source and destination)
        let crdtMirror = Mirror(reflecting: crdt)
        let crdtProperties: Set<String> = Set(crdtMirror.children.compactMap(\.label))

        let snapshotMirror = Mirror(reflecting: snapshot)
        let snapshotProperties: Set<String> = Set(snapshotMirror.children.compactMap(\.label))

        // Every CRDTDocument property should have a corresponding snapshot field
        let missing = crdtProperties.subtracting(snapshotProperties)
        #expect(missing.isEmpty, "CRDTDocument properties not in CRDTSnapshot: \(missing)")
    }

    // MARK: - Clock advancement

    @Test("Clock advancement prevents collisions after init from snapshot")
    func clockAdvancementPreventsCollisions() throws {
        let editableA = EditableDocument(from: makeDoc(), peerID: peerA)
        // Make several edits to advance A's clock
        _ = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Edit 1"))
        ))
        _ = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Edit 2"))
        ))

        let snapshot = try #require(editableA.crdtDocument?.snapshot())
        let maxSnapshotTime = snapshot.operationLog.clock.time

        // B inits from snapshot
        let crdtB = CRDTDocument(from: snapshot, peerID: peerB)

        // B's clock should be past the snapshot's clock
        #expect(crdtB.operationLog.clock.time > maxSnapshotTime)
    }
}

/// Helper for Sendable compile-time check
private nonisolated func acceptSendable(_: some Sendable) {}
