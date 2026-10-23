//
//  RemoteInputBoundsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A remote peer's clock values are refused at the boundary, before they can overflow
/// the local clock (the multiplayer relay's security review, H5; leaf Ol1s6D).
@MainActor
struct RemoteInputBoundsTests {
    private let local = PeerID(rawValue: "local")
    private let remote = PeerID(rawValue: "remote")

    private func document() -> EditableDocument {
        EditableDocument(from: FuzzFixture.document(), peerID: local)
    }

    private func rename(_ nodeID: String, to name: String, time: UInt64, dependencies: VectorClock = VectorClock()) -> CRDTOperation {
        CRDTOperation(
            id: Timestamp(time: time, peerID: remote),
            dependencies: dependencies,
            payload: .setProperty(.init(nodeID: nodeID, property: "common.name", value: .string(name)))
        )
    }

    @Test("A remote time of UInt64.max is refused and leaves the document as it was")
    func maximumTimeIsRefused() throws {
        let editable = document()
        let before = RemoteInputState(editable)
        let operation = rename("r1", to: "Hijacked", time: .max)

        let crdt = try #require(editable.crdtDocument)
        #expect(throws: RemoteInputError.timeOutOfRange(operation: operation.id, localTime: 0)) {
            try crdt.validateRemote(operation)
        }
        let refused = editable.applyRemote(operation)

        #expect(refused == .timeOutOfRange(operation: operation.id, localTime: 0))
        #expect(RemoteInputState(editable) == before)
        // The clock still works for the next local edit.
        _ = try editable.applyLocal(.updateCommon(.init(nodeID: "r1", common: PenNodeCommon(name: "Mine"))))
        #expect(editable.nodes["r1"]?.common.name == "Mine")
    }

    @Test("A remote time past the clock's lead is refused, one just inside it is taken")
    func leadBound() throws {
        let editable = document()
        let crdt = try #require(editable.crdtDocument)
        let localTime = crdt.operationLog.clock.time

        let tooFar = rename("r1", to: "Far", time: localTime + LamportClock.maximumLead + 1)
        #expect(editable.applyRemote(tooFar) != nil)
        #expect(editable.nodes["r1"]?.common.name == "Rect1")

        let honest = rename("r1", to: "Near", time: localTime + LamportClock.maximumLead)
        #expect(editable.applyRemote(honest) == nil)
        #expect(editable.nodes["r1"]?.common.name == "Near")
    }

    @Test("A remote time past the ceiling is refused even when the clock is near it")
    func ceilingBound() {
        #expect(!LamportClock.admits(LamportClock.ceiling + 1, after: LamportClock.ceiling))
        #expect(LamportClock.admits(LamportClock.ceiling, after: LamportClock.ceiling - 1))
        #expect(!LamportClock.admits(.max, after: .max - 1))
        #expect(LamportClock.ceiling <= UInt64.max / 2)
    }

    @Test("A dependency entry of UInt64.max for this replica is refused")
    func dependencyOnThisReplicaIsRefused() throws {
        let editable = document()
        let before = RemoteInputState(editable)
        var dependencies = VectorClock()
        dependencies.entries[local] = .max
        let operation = rename("r1", to: "Hijacked", time: 1, dependencies: dependencies)

        let refused = editable.applyRemote(operation)

        #expect(refused == .dependencyOutOfRange(operation: operation.id, peer: local, time: .max, localTime: 0))
        #expect(RemoteInputState(editable) == before)
        _ = try editable.applyLocal(.updateCommon(.init(nodeID: "r1", common: PenNodeCommon(name: "Mine"))))
        #expect(editable.nodes["r1"]?.common.name == "Mine")
    }

    @Test("A batch keeps the honest operations and reports the refused one")
    func batchReportsRefusals() {
        let editable = document()
        let bad = rename("r1", to: "Hijacked", time: .max)
        let good = rename("r2", to: "Renamed", time: 1)

        let refused = editable.applyRemote([bad, good])

        #expect(refused == [.timeOutOfRange(operation: bad.id, localTime: 0)])
        #expect(editable.nodes["r1"]?.common.name == "Rect1")
        #expect(editable.nodes["r2"]?.common.name == "Renamed")
    }

    @Test("A session reports a refused remote operation on the committed change")
    func sessionReportsRefusals() throws {
        let session = DocumentSession(document: FuzzFixture.document(), author: .unattributed(peer: local), collaborative: true)
        let bad = rename("r1", to: "Hijacked", time: .max)
        let good = rename("r2", to: "Renamed", time: 1)

        let change = try session.submit(.remote([bad, good], from: .unattributed(peer: remote)))

        #expect(change.rejected == [.timeOutOfRange(operation: bad.id, localTime: 0)])
        #expect(session.document.nodes["r1"]?.common.name == "Rect1")
        #expect(session.document.nodes["r2"]?.common.name == "Renamed")
    }

    @Test("A snapshot whose clock is past the ceiling is refused")
    func snapshotClockIsRefused() throws {
        let source = document()
        var snapshot = try #require(source.crdtDocument?.snapshot())
        snapshot.operationLog.clock = LamportClock(time: .max)

        #expect(throws: RemoteInputError.snapshotTimeOutOfRange(time: .max)) {
            _ = try EditableDocument(from: FuzzFixture.document(), snapshot: snapshot, peerID: remote)
        }
    }

    @Test("A snapshot whose vector clock is past the ceiling is refused")
    func snapshotVectorClockIsRefused() throws {
        let source = document()
        var snapshot = try #require(source.crdtDocument?.snapshot())
        snapshot.operationLog.vectorClock.entries[remote] = .max

        #expect(throws: RemoteInputError.snapshotTimeOutOfRange(time: .max)) {
            _ = try CRDTDocument(from: snapshot, peerID: remote)
        }
    }

    @Test("A snapshot whose tree holds a cycle is refused rather than hanging the next move")
    func snapshotCycleIsRefused() throws {
        let source = document()
        var snapshot = try #require(source.crdtDocument?.snapshot())
        snapshot.treeMove.parentMap["f1"] = "r1"
        snapshot.treeMove.parentMap["r1"] = "f1"

        #expect(throws: RemoteInputError.self) {
            _ = try CRDTDocument(from: snapshot, peerID: remote)
        }
    }

    @Test("A remote create that names the node as its own parent leaves no parent cycle")
    func selfParentedCreate() {
        let editable = document()
        let node = PenNode(id: "loop", common: PenNodeCommon(name: "Loop"), kind: .frame(PenNode.FrameData()))
        let operation = CRDTOperation(
            id: Timestamp(time: 1, peerID: remote),
            dependencies: VectorClock(),
            payload: .createNode(.init(node: node, parentID: "loop"))
        )

        editable.applyRemote(operation)

        #expect(editable.parents["loop"] == nil)
        #expect(RemoteInputState.parentCycle(in: editable) == nil)
    }

    @Test("A remote operation nested past the decoder's depth fails to decode rather than trapping")
    func deepNestingFailsToDecode() throws {
        let depth = 100_000
        let value = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let json = """
        {"id":{"time":1,"peerID":"remote"},"dependencies":{"entries":[]},
         "payload":{"setProperty":{"_0":{"nodeID":"r1","property":"common.name","value":\(value)}}}}
        """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CRDTOperation.self, from: Data(json.utf8))
        }
    }
}
