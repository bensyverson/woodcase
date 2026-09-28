//
//  CRDTDocumentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTDocumentTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    private func makeDoc() -> EditableDocument {
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
        return EditableDocument(from: PenDocument(children: [frame]))
    }

    // MARK: - processLocal

    @Test("processLocal for insertNode produces createNode + listInsert ops")
    func processLocalInsertNode() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let newNode = PenNode(
            id: "n2",
            common: PenNodeCommon(name: "New"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let editOp = EditOperation.insertNode(EditOperation.InsertNode(node: newNode, parentID: "f1"))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let hasCreateNode = ops.contains { op in
            if case .createNode = op.payload { return true }
            return false
        }
        let hasListInsert = ops.contains { op in
            if case .listInsert = op.payload { return true }
            return false
        }
        #expect(hasCreateNode)
        #expect(hasListInsert)
    }

    @Test("processLocal for deleteNode produces deleteNode + listDelete ops")
    func processLocalDeleteNode() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let editOp = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "r1"))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let hasDeleteNode = ops.contains { op in
            if case .deleteNode = op.payload { return true }
            return false
        }
        let hasListDelete = ops.contains { op in
            if case .listDelete = op.payload { return true }
            return false
        }
        #expect(hasDeleteNode)
        #expect(hasListDelete)
    }

    @Test("processLocal for moveNode produces treeMove + list ops")
    func processLocalMoveNode() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Move r1 from f1 to root
        let editOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: nil))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let hasTreeMove = ops.contains { op in
            if case .treeMove = op.payload { return true }
            return false
        }
        #expect(hasTreeMove)
    }

    @Test("processLocal for updateCommon diffs and produces per-property setProperty ops")
    func processLocalUpdateCommon() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let newCommon = PenNodeCommon(name: "Renamed", opacity: .literal(0.5))
        let editOp = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "r1", common: newCommon))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        // Should produce setProperty ops for name and opacity (at minimum)
        let propertyOps = ops.compactMap { op -> String? in
            if case let .setProperty(p) = op.payload { return p.property }
            return nil
        }
        #expect(propertyOps.contains("common.name"))
        #expect(propertyOps.contains("common.opacity"))
    }

    @Test("processLocal for updateKind diffs and produces per-property setProperty ops")
    func processLocalUpdateKind() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let newKind = PenNode.Kind.rectangle(PenNode.RectangleData(width: .fixed(200)))
        let editOp = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "r1", kind: newKind))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let propertyOps = ops.compactMap { op -> String? in
            if case let .setProperty(p) = op.payload { return p.property }
            return nil
        }
        #expect(propertyOps.contains("kind.width"))
    }

    // MARK: - processRemote

    @Test("processRemote for setProperty on live node returns mutations")
    func processRemoteSetPropertyLive() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .setProperty(CRDTOperation.SetProperty(
                nodeID: "r1",
                property: "common.name",
                value: AnyCodable("RemoteName")
            ))
        )

        let mutations = crdt.processRemote(operation: remoteOp, document: doc)
        #expect(mutations != nil)
        #expect(mutations?.isEmpty == false)
    }

    @Test("processRemote for setProperty on tombstoned node returns nil")
    func processRemoteSetPropertyTombstoned() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Tombstone r1
        crdt.tombstones.insert("r1")

        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .setProperty(CRDTOperation.SetProperty(
                nodeID: "r1",
                property: "common.name",
                value: AnyCodable("Ghost")
            ))
        )

        let mutations = crdt.processRemote(operation: remoteOp, document: doc)
        #expect(mutations == nil)
    }

    @Test("processRemote for treeMove that would create cycle returns nil")
    func processRemoteTreeMoveCycle() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Try to move f1 under r1 — r1 is already under f1, so this creates a cycle
        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .treeMove(CRDTOperation.TreeMove(
                nodeID: "f1",
                newParentID: "r1"
            ))
        )

        let mutations = crdt.processRemote(operation: remoteOp, document: doc)
        #expect(mutations == nil)
    }

    @Test("processRemote for createNode returns mutations")
    func processRemoteCreateNode() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let newNode = PenNode(
            id: "n3",
            common: PenNodeCommon(name: "Remote"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .createNode(CRDTOperation.CreateNode(
                node: newNode,
                parentID: "f1"
            ))
        )

        let mutations = crdt.processRemote(operation: remoteOp, document: doc)
        #expect(mutations != nil)
    }

    @Test("processRemote for deleteNode returns mutations and tombstones")
    func processRemoteDeleteNode() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "r1"))
        )

        let mutations = crdt.processRemote(operation: remoteOp, document: doc)
        #expect(mutations != nil)
        #expect(crdt.tombstones.contains("r1"))
    }

    // MARK: - Document-level operations

    @Test("processLocal for setVariable produces setVariable op")
    func processLocalSetVariable() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#FF0000")))
        let editOp = EditOperation.addVariable(EditOperation.AddVariable(name: "primary", variable: variable))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let hasSetVar = ops.contains { op in
            if case .setVariable = op.payload { return true }
            return false
        }
        #expect(hasSetVar)
    }

    @Test("processLocal for addImport produces setImport op")
    func processLocalSetImport() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let editOp = EditOperation.addImport(EditOperation.AddImport(alias: "icons", path: "./icons.pen"))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let hasSetImport = ops.contains { op in
            if case .setImport = op.payload { return true }
            return false
        }
        #expect(hasSetImport)
    }

    @Test("processLocal for addThemeAxis produces setThemeAxis op")
    func processLocalSetThemeAxis() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let editOp = EditOperation.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"]))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let hasSetTheme = ops.contains { op in
            if case .setThemeAxis = op.payload { return true }
            return false
        }
        #expect(hasSetTheme)
    }
}
