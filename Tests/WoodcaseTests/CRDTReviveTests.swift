//
//  CRDTReviveTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A node's existence is a last-writer-wins register per id: a create newer than the
/// id's latest existence write brings a deleted node back, a delete newer than it removes
/// the node, and property writes that arrive while the node is deleted are kept for its
/// return — so collaborative undo of a delete converges on every peer.
@MainActor
struct CRDTReviveTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")
    private let peerC = PeerID(rawValue: "ccc")
    private let peerD = PeerID(rawValue: "ddd")

    private static let rect = PenNode(id: "r1", common: PenNodeCommon(name: "Rect"), kind: .rectangle(PenNode.RectangleData()))

    /// `f1 > [r0, r1, r2]`, and `loose` at the root.
    private func makeDoc() -> PenDocument {
        let r0 = PenNode(id: "r0", common: PenNodeCommon(name: "Zero"), kind: .rectangle(PenNode.RectangleData()))
        let r2 = PenNode(id: "r2", common: PenNodeCommon(name: "Two"), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(id: "f1", common: PenNodeCommon(name: "Frame"), kind: .frame(PenNode.FrameData(children: [r0, Self.rect, r2])))
        let loose = PenNode(id: "loose", common: PenNodeCommon(name: "Loose"), kind: .rectangle(PenNode.RectangleData()))
        return PenDocument(children: [frame, loose])
    }

    private func replica(_ peer: PeerID) -> EditableDocument {
        EditableDocument(from: makeDoc(), peerID: peer)
    }

    private func rename(_ id: String, _ name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: id, properties: ["common.name": .string(name)]))
    }

    private func delete(_ id: String) -> EditOperation {
        .deleteNode(EditOperation.DeleteNode(nodeID: id))
    }

    /// What undo of `delete("r1")` applies: `r1` as it was, back at its index in `f1`.
    private var reinsertRect: EditOperation {
        .insertNode(EditOperation.InsertNode(node: Self.rect, parentID: "f1", index: 1))
    }

    /// Advances a replica's Lamport clock by making `count` writes to a node no test reads.
    private func tick(_ doc: EditableDocument, _ count: Int) throws -> [CRDTOperation] {
        var ops: [CRDTOperation] = []
        for i in 0 ..< count {
            ops += try doc.applyLocal(rename("loose", "\(doc.crdtDocument!.peerID.rawValue)\(i)"))
        }
        return ops
    }

    private func expectConverged(_ docs: [EditableDocument], sourceLocation: SourceLocation = #_sourceLocation) {
        guard let first = docs.first else { return }
        for doc in docs.dropFirst() {
            #expect(doc.materialize() == first.materialize(), sourceLocation: sourceLocation)
            #expect(doc.nodes == first.nodes, sourceLocation: sourceLocation)
            #expect(doc.parents == first.parents, sourceLocation: sourceLocation)
            #expect(doc.children == first.children, sourceLocation: sourceLocation)
            #expect(doc.rootOrder == first.rootOrder, sourceLocation: sourceLocation)
            #expect(doc.crdtDocument?.tombstones == first.crdtDocument?.tombstones, sourceLocation: sourceLocation)
        }
    }

    // MARK: - The regression

    @Test("undo of a delete, then a rename, converges on a peer that receives all three")
    func undoOfDeleteThenRenameConverges() throws {
        let ana = Author(name: "ana", peerID: peerA)
        let bo = Author(name: "bo", peerID: peerB)
        let a = DocumentSession(document: makeDoc(), author: ana, file: nil, collaborative: true)
        let b = DocumentSession(document: makeDoc(), author: bo, file: nil, collaborative: true)

        let deleted = try a.submit(.local(LocalEdit(operations: [delete("r1")])))
        let undone = try a.submit(.undo)
        let renamed = try a.submit(.local(LocalEdit(operations: [rename("r1", "After")])))
        try b.submit(.remote(deleted.broadcast + undone.broadcast + renamed.broadcast, from: ana))

        #expect(a.document.nodes["r1"]?.common.name == "After")
        #expect(b.document.nodes["r1"]?.common.name == "After")
        #expect(b.document.children["f1"] == ["r0", "r1", "r2"])
        #expect(a.document.crdtDocument?.tombstones.contains("r1") == false)
        #expect(b.document.crdtDocument?.tombstones.contains("r1") == false)
        expectConverged([a.document, b.document])
    }

    // MARK: - Concurrent delete and revive

    @Test("a concurrent delete newer than the revive removes the node on every peer")
    func newerDeleteBeatsRevive() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC), d = replica(peerD)
        let opsA = try a.applyLocal(delete("r1")) + a.applyLocal(reinsertRect)
        let opsB = try tick(b, 20) + b.applyLocal(delete("r1"))
        a.applyRemote(opsB)
        b.applyRemote(opsA)
        c.applyRemote(opsA + opsB)
        d.applyRemote(opsB + opsA)

        for doc in [a, b, c, d] {
            #expect(doc.nodes["r1"] == nil)
            #expect(doc.children["f1"] == ["r0", "r2"])
        }
        expectConverged([a, b, c, d])
    }

    @Test("a revive newer than a concurrent delete keeps the node on every peer, where the undo put it")
    func newerReviveBeatsDelete() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC), d = replica(peerD)
        let opsB = try b.applyLocal(delete("r1"))
        let opsA = try a.applyLocal(delete("r1")) + tick(a, 20) + a.applyLocal(reinsertRect)
        a.applyRemote(opsB)
        b.applyRemote(opsA)
        c.applyRemote(opsA + opsB)
        d.applyRemote(opsB + opsA)

        for doc in [a, b, c, d] {
            #expect(doc.nodes["r1"]?.common.name == "Rect")
            #expect(doc.children["f1"] == ["r0", "r1", "r2"])
        }
        expectConverged([a, b, c, d])
    }

    // MARK: - Writes while deleted

    @Test("a write newer than the delete and the revive, arriving while the node is deleted, applies when it returns")
    func writeWhileDeletedAppliesOnReturn() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC)
        let deleted = try a.applyLocal(delete("r1"))
        let write = try tick(c, 20) + c.applyLocal(rename("r1", "Late"))
        let revived = try a.applyLocal(reinsertRect)
        #expect(try #require(write.last).id > #require(revived.first).id)

        // b: the write lands between the delete and the revive.
        b.applyRemote(deleted)
        b.applyRemote(write)
        b.applyRemote(revived)
        // a: after its own revive. c: the delete and revive after its write.
        a.applyRemote(write)
        c.applyRemote(deleted + revived)

        for doc in [a, b, c] {
            #expect(doc.nodes["r1"]?.common.name == "Late")
        }
        expectConverged([a, b, c])
    }

    @Test("a write older than the revive loses to it, whenever it arrives")
    func writeOlderThanReviveLoses() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC), d = replica(peerD)
        let write = try c.applyLocal(rename("r1", "Stale"))
        let opsA = try a.applyLocal(delete("r1")) + tick(a, 20) + a.applyLocal(reinsertRect)
        a.applyRemote(write)
        b.applyRemote(write + opsA)
        c.applyRemote(opsA)
        d.applyRemote(opsA + write)

        for doc in [a, b, c, d] {
            #expect(doc.nodes["r1"]?.common.name == "Rect")
        }
        expectConverged([a, b, c, d])
    }

    @Test("a write newer than the delete, applied before the delete arrives, survives to the revive")
    func writeAppliedBeforeDeleteSurvives() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC)
        let deleted = try a.applyLocal(delete("r1"))
        let write = try tick(c, 20) + c.applyLocal(rename("r1", "Late"))
        let revived = try a.applyLocal(reinsertRect)

        // b takes the write while r1 is alive, then the delete, then the revive.
        b.applyRemote(write)
        b.applyRemote(deleted)
        b.applyRemote(revived)
        a.applyRemote(write)
        c.applyRemote(deleted + revived)

        for doc in [a, b, c] {
            #expect(doc.nodes["r1"]?.common.name == "Late")
        }
        expectConverged([a, b, c])
    }

    @Test("a write to a deleted node does not bring it back")
    func writeDoesNotRevive() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC)
        let deleted = try a.applyLocal(delete("r1"))
        let write = try tick(c, 20) + c.applyLocal(rename("r1", "Late"))
        b.applyRemote(deleted + write)
        a.applyRemote(write)
        c.applyRemote(deleted)

        for doc in [a, b, c] {
            #expect(doc.nodes["r1"] == nil)
        }
        expectConverged([a, b, c])
    }

    // MARK: - Placement

    @Test("a revived container takes back its revived children")
    func revivedContainerKeepsChildren() throws {
        let a = replica(peerA), b = replica(peerB)
        let original = try #require(a.materialize().children.first { $0.id == "f1" })
        let deleted = try a.applyLocal(delete("f1"))
        let revived = try a.applyLocal(.insertNode(EditOperation.InsertNode(node: original, parentID: nil, index: 0)))
        b.applyRemote(deleted + revived)

        for doc in [a, b] {
            #expect(doc.rootOrder == ["f1", "loose"])
            #expect(doc.children["f1"] == ["r0", "r1", "r2"])
        }
        expectConverged([a, b])
    }

    @Test("a node moved into a container while it was deleted returns with the container")
    func nodeMovedIntoDeletedContainerReturns() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC)
        let original = try #require(a.materialize().children.first { $0.id == "f1" })
        let opsA = try a.applyLocal(delete("f1"))
            + a.applyLocal(.insertNode(EditOperation.InsertNode(node: original, parentID: nil, index: 0)))
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "loose", newParentID: "f1", index: nil)))
        a.applyRemote(opsB)
        b.applyRemote(opsA)
        c.applyRemote(opsB + opsA)

        for doc in [a, b, c] {
            #expect(doc.parents["loose"] == "f1")
            #expect(doc.children["f1"]?.contains("loose") == true)
        }
        expectConverged([a, b, c])
    }

    // MARK: - Joining and replay

    @Test("a peer joining while a write is kept for a deleted node converges when the node returns")
    func joinerCarriesKeptWrites() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC)
        let deleted = try a.applyLocal(delete("r1"))
        let write = try tick(c, 20) + c.applyLocal(rename("r1", "Late"))
        let revived = try a.applyLocal(reinsertRect)
        b.applyRemote(deleted + write)

        let transfer = try #require(b.stateTransfer())
        let decoded = try JSONDecoder().decode(CRDTStateTransfer.self, from: JSONEncoder().encode(transfer))
        #expect(decoded == transfer)
        let joiner = try EditableDocument(joining: decoded, peerID: peerD)
        joiner.applyRemote(revived)
        b.applyRemote(revived)
        a.applyRemote(write)
        c.applyRemote(deleted + revived)

        for doc in [a, b, c, joiner] {
            #expect(doc.nodes["r1"]?.common.name == "Late")
        }
        expectConverged([a, b, c, joiner])
    }

    @Test("a fresh replica replaying every peer's log in reverse converges")
    func reverseReplayConverges() throws {
        let a = replica(peerA), b = replica(peerB), c = replica(peerC)
        let deleted = try a.applyLocal(delete("r1"))
        let write = try tick(c, 20) + c.applyLocal(rename("r1", "Late"))
        let revived = try a.applyLocal(reinsertRect)
        let renamed = try a.applyLocal(rename("r1", "After"))
        b.applyRemote(deleted + write + revived + renamed)
        a.applyRemote(write)
        c.applyRemote(deleted + revived + renamed)

        let fresh = replica(peerD)
        fresh.applyRemote((deleted + write + revived + renamed).reversed())
        #expect(fresh.crdtDocument?.heldOperations.isEmpty == true)
        expectConverged([a, b, c, fresh])
    }
}
