//
//  EditableDocumentCRDTTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditableDocumentCRDTTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    private func makeDoc() -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect", opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect]))
        )
        return PenDocument(children: [frame])
    }

    // MARK: - Initialization

    @Test("init(from:peerID:) sets crdtDocument to non-nil")
    func initWithPeerIDSetsCRDT() {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        #expect(editable.crdtDocument != nil)
    }

    @Test("init(from:) without peerID leaves crdtDocument nil")
    func initWithoutPeerIDLeavesCRDTNil() {
        let editable = EditableDocument(from: makeDoc())
        #expect(editable.crdtDocument == nil)
    }

    @Test("init(from:) without peerID still allows apply()")
    func initWithoutPeerIDApplyStillWorks() throws {
        let editable = EditableDocument(from: makeDoc())
        let newNode = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "New"),
            kind: .rectangle(PenNode.RectangleData())
        )
        try editable.apply(.insertNode(EditOperation.InsertNode(node: newNode, parentID: "f1")))
        #expect(editable.nodes["n1"] != nil)
    }

    // MARK: - applyLocal

    @Test("applyLocal insertNode returns CRDTOperations and updates flat store")
    func applyLocalInsertNode() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        let newNode = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "New"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let ops = try editable.applyLocal(.insertNode(EditOperation.InsertNode(node: newNode, parentID: "f1")))
        #expect(!ops.isEmpty)
        #expect(editable.nodes["n1"] != nil)
        #expect(editable.children["f1"]?.contains("n1") == true)
    }

    @Test("applyLocal updateCommon returns per-property setProperty ops")
    func applyLocalUpdateCommon() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        let newCommon = PenNodeCommon(name: "Renamed", opacity: .literal(0.5))
        let ops = try editable.applyLocal(.updateCommon(EditOperation.UpdateCommon(nodeID: "r1", common: newCommon)))

        let propertyPaths = ops.compactMap { op -> String? in
            if case let .setProperty(p) = op.payload { return p.property }
            return nil
        }
        #expect(propertyPaths.contains("common.name"))
        #expect(propertyPaths.contains("common.opacity"))
        #expect(editable.nodes["r1"]?.common.name == "Renamed")
    }

    @Test("applyLocal deleteNode returns ops and removes node from store")
    func applyLocalDeleteNode() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        let ops = try editable.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "r1")))

        let hasDelete = ops.contains { if case .deleteNode = $0.payload { return true }; return false }
        #expect(hasDelete)
        #expect(editable.nodes["r1"] == nil)
    }

    // MARK: - applyRemote

    @Test("applyRemote with property change updates flat store")
    func applyRemotePropertyChange() {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .setProperty(CRDTOperation.SetProperty(
                nodeID: "r1",
                property: "common.name",
                value: AnyCodable("RemoteName")
            ))
        )
        editable.applyRemote(remoteOp)
        #expect(editable.nodes["r1"]?.common.name == "RemoteName")
    }

    @Test("applyRemote with stale timestamp is a no-op (LWW rejects)")
    func applyRemoteStaleTimestamp() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        // First, do a local edit to bump the property timestamp
        let newCommon = PenNodeCommon(name: "LocalName", opacity: .literal(1.0))
        _ = try editable.applyLocal(.updateCommon(EditOperation.UpdateCommon(nodeID: "r1", common: newCommon)))

        // Now apply a remote op with a lower timestamp — should be rejected
        let staleOp = CRDTOperation(
            id: Timestamp(time: 0, peerID: peerB),
            dependencies: VectorClock(),
            payload: .setProperty(CRDTOperation.SetProperty(
                nodeID: "r1",
                property: "common.name",
                value: AnyCodable("StaleName")
            ))
        )
        editable.applyRemote(staleOp)
        #expect(editable.nodes["r1"]?.common.name == "LocalName")
    }

    @Test("applyRemote with delete tombstones node")
    func applyRemoteDeleteTombstones() {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        let deleteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "r1"))
        )
        editable.applyRemote(deleteOp)
        #expect(editable.nodes["r1"] == nil)
    }

    @Test("applyRemote batch applies multiple ops")
    func applyRemoteBatch() {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        let newNode = PenNode(
            id: "n2",
            common: PenNodeCommon(name: "Remote"),
            kind: .rectangle(PenNode.RectangleData())
        )

        let ops: [CRDTOperation] = [
            CRDTOperation(
                id: Timestamp(time: 10, peerID: peerB),
                dependencies: VectorClock(),
                payload: .createNode(CRDTOperation.CreateNode(node: newNode, parentID: "f1"))
            ),
            CRDTOperation(
                id: Timestamp(time: 11, peerID: peerB),
                dependencies: VectorClock(),
                payload: .setProperty(CRDTOperation.SetProperty(
                    nodeID: "r1",
                    property: "common.name",
                    value: AnyCodable("BatchRenamed")
                ))
            ),
        ]
        editable.applyRemote(ops)
        #expect(editable.nodes["n2"] != nil)
        #expect(editable.nodes["r1"]?.common.name == "BatchRenamed")
    }

    // MARK: - pendingOperations

    @Test("pendingOperations(since:) returns correct subset")
    func pendingOperationsSince() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        let emptyVC = VectorClock()
        // Before any ops, pending should be empty
        #expect(editable.pendingOperations(since: emptyVC).isEmpty)

        // Make a local edit
        let newCommon = PenNodeCommon(name: "Changed")
        _ = try editable.applyLocal(.updateCommon(EditOperation.UpdateCommon(nodeID: "r1", common: newCommon)))

        let pending = editable.pendingOperations(since: emptyVC)
        #expect(!pending.isEmpty)

        // If we pass the operation log's vector clock, nothing should be pending
        let currentVC = try #require(editable.crdtDocument?.operationLog.vectorClock)
        #expect(editable.pendingOperations(since: currentVC).isEmpty)
    }

    // MARK: - materialize after remote ops

    @Test("materialize() after remote ops produces correct PenDocument")
    func materializeAfterRemoteOps() {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)

        // Remote rename
        let renameOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .setProperty(CRDTOperation.SetProperty(
                nodeID: "f1",
                property: "common.name",
                value: AnyCodable("RemoteFrame")
            ))
        )
        editable.applyRemote(renameOp)

        let materialized = editable.materialize()
        #expect(materialized.children.first?.common.name == "RemoteFrame")
    }
}
