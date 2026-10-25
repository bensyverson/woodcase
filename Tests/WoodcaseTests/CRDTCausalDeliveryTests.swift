//
//  CRDTCausalDeliveryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A replica takes remote operations in causal order whatever order they arrive in: one
/// whose causal past has not arrived is held until it has, and one it already took is
/// ignored.
@MainActor
struct CRDTCausalDeliveryTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")
    private let peerC = PeerID(rawValue: "ccc")

    private func makeDoc() -> PenDocument {
        let rect = PenNode(id: "r1", common: PenNodeCommon(name: "Rect"), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(id: "f1", common: PenNodeCommon(name: "Frame"), kind: .frame(PenNode.FrameData(children: [rect])))
        return PenDocument(children: [frame])
    }

    private func insert(_ id: String, into parentID: String?) -> EditOperation {
        let node = PenNode(id: id, common: PenNodeCommon(name: id), kind: .rectangle(PenNode.RectangleData()))
        return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID))
    }

    private func rename(_ id: String, _ name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: id, properties: ["common.name": .string(name)]))
    }

    // MARK: - Clocks

    @Test("a replica's vector clock entry is the Lamport time of its latest operation")
    func vectorClockHoldsLamportTimes() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let ops = try a.applyLocal(insert("n1", into: "f1"))
        let last = try #require(ops.last)
        #expect(a.crdtDocument?.operationLog.vectorClock.time(for: peerA) == last.id.time)
    }

    @Test("an operation's dependencies are its causal past, without the operation itself")
    func dependenciesExcludeTheOperation() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let ops = try a.applyLocal(insert("n1", into: "f1"))
        #expect(ops.count >= 2)
        #expect(ops[0].dependencies.time(for: peerA) == 0)
        #expect(ops[1].dependencies.time(for: peerA) == ops[0].id.time)
    }

    @Test("a vector clock covers an operation id at or below its entry for that peer")
    func vectorClockCovers() {
        var clock = VectorClock()
        clock.record(Timestamp(time: 7, peerID: peerA))
        #expect(clock.covers(Timestamp(time: 7, peerID: peerA)))
        #expect(clock.covers(Timestamp(time: 3, peerID: peerA)))
        #expect(!clock.covers(Timestamp(time: 8, peerID: peerA)))
        #expect(!clock.covers(Timestamp(time: 1, peerID: peerB)))
    }

    @Test("pending operations are the ones a clock does not cover")
    func pendingUsesCoverage() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let first = try a.applyLocal(rename("r1", "One"))
        let second = try a.applyLocal(rename("r1", "Two"))
        var seen = VectorClock()
        try seen.record(#require(first.last).id)
        #expect(a.pendingOperations(since: seen) == second)
    }

    // MARK: - Holding

    @Test("a write that arrives before the node it targets is held, then applied when the node arrives")
    func writeBeforeCreateIsHeld() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        let create = try a.applyLocal(insert("n1", into: "f1"))
        let write = try a.applyLocal(rename("n1", "Named"))

        b.applyRemote(write)
        #expect(b.nodes["n1"] == nil)
        #expect(b.crdtDocument?.heldOperations.count == write.count)

        b.applyRemote(create)
        #expect(b.nodes["n1"]?.common.name == "Named")
        #expect(b.crdtDocument?.heldOperations.isEmpty == true)
        #expect(b.children["f1"] == a.children["f1"])
    }

    @Test("an operation that depends on a third peer's operation waits for it")
    func waitsForThirdPeer() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        let c = EditableDocument(from: makeDoc(), peerID: peerC)
        let fromA = try a.applyLocal(insert("n1", into: "f1"))
        b.applyRemote(fromA)
        let fromB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "n1", newParentID: nil, index: 0)))

        c.applyRemote(fromB)
        #expect(c.crdtDocument?.heldOperations.count == fromB.count)
        c.applyRemote(fromA)
        #expect(c.crdtDocument?.heldOperations.isEmpty == true)
        #expect(c.rootOrder == b.rootOrder)
        #expect(c.parents == b.parents)
    }

    // MARK: - Duplicates

    @Test("an operation delivered twice is applied once")
    func duplicateIsIgnored() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        let ops = try a.applyLocal(insert("n1", into: "f1"))

        b.applyRemote(ops)
        let logCount = b.crdtDocument?.operationLog.operations.count
        b.applyRemote(ops)
        #expect(b.children["f1"] == ["r1", "n1"])
        #expect(b.crdtDocument?.childrenLists["f1"]?.entries.count == 2)
        #expect(b.crdtDocument?.operationLog.operations.count == logCount)
    }

    @Test("an operation held twice is held once")
    func heldDuplicateIsHeldOnce() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        _ = try a.applyLocal(insert("n1", into: "f1"))
        let write = try a.applyLocal(rename("n1", "Named"))

        b.applyRemote(write)
        b.applyRemote(write)
        #expect(b.crdtDocument?.heldOperations.count == write.count)
    }

    @Test("a replica's own operation coming back is ignored")
    func ownEchoIsIgnored() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let ops = try a.applyLocal(insert("n1", into: "f1"))
        let before = a.crdtDocument?.operationLog.operations.count
        a.applyRemote(ops)
        #expect(a.children["f1"] == ["r1", "n1"])
        #expect(a.crdtDocument?.operationLog.operations.count == before)
    }

    // MARK: - The session

    @Test("a session holds an out-of-order write and credits it to its author when it lands")
    func sessionHoldsAndCredits() throws {
        let ana = Author(name: "ana", peerID: peerA)
        let bo = Author(name: "bo", peerID: peerB)
        let session = DocumentSession(document: makeDoc(), author: ana, file: nil, collaborative: true)
        let peer = SessionTestPeer(bo, document: makeDoc())
        let create = try peer.edit(insert("n1", into: "f1"))
        let write = try peer.edit(rename("n1", "Named"))

        let early = try session.submit(.remote(write, from: bo))
        #expect(early.sequence == 0)
        #expect(session.document.nodes["n1"] == nil)

        let late = try session.submit(.remote(create, from: bo))
        #expect(session.document.nodes["n1"]?.common.name == "Named")
        #expect(late.invalidation.nodes.contains("n1"))
        #expect(session.ledger.stamp(for: .property(node: "n1", path: "common.name"))?.author == bo)
    }
}
