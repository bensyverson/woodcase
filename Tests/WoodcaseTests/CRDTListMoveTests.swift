//
//  CRDTListMoveTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTListMoveTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    /// Document: root → [frame(f1) → [rect(r1), rect(r2)]]
    private func makeDoc() -> EditableDocument {
        let r1 = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "R1"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let r2 = PenNode(
            id: "r2",
            common: PenNodeCommon(name: "R2"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(children: [r1, r2]))
        )
        return EditableDocument(from: PenDocument(children: [frame]))
    }

    // MARK: - Step 2: processLocalMove emits atomic listMove

    @Test("processLocalMove emits a single listMove op, not listDelete + listInsert")
    func processLocalMoveEmitsListMoveOp() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Move r1 from f1 to root
        let editOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: nil))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let listMoveCount = ops.count { if case .listMove = $0.payload { return true }; return false }
        let listDeleteCount = ops.count { if case .listDelete = $0.payload { return true }; return false }
        let listInsertCount = ops.count { if case .listInsert = $0.payload { return true }; return false }

        #expect(listMoveCount == 1, "Expected exactly one listMove op")
        #expect(listDeleteCount == 0, "Expected no listDelete ops")
        #expect(listInsertCount == 0, "Expected no listInsert ops")
    }

    @Test("processLocalMove uses tree CRDT parentMap, not flat store")
    func processLocalMoveUsesTreeCRDTParentMap() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Move r1 from f1 to root via processLocal
        let editOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: nil))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        // The listMove should reference sourceListID "f1" (from tree CRDT, where r1's parent is f1)
        let listMoveOp = ops.compactMap { op -> CRDTOperation.ListMove? in
            if case let .listMove(lm) = op.payload { return lm }
            return nil
        }.first

        #expect(listMoveOp != nil)
        #expect(listMoveOp?.sourceListID == "f1", "Source list should come from tree CRDT parent")
    }

    @Test("processLocalMove to root sets targetListID to __root__")
    func processLocalMoveToRoot() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let editOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: nil))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let listMoveOp = ops.compactMap { op -> CRDTOperation.ListMove? in
            if case let .listMove(lm) = op.payload { return lm }
            return nil
        }.first

        #expect(listMoveOp?.targetListID == CRDTDocument.rootListID)
    }

    @Test("processLocalMove within same parent keeps sourceListID == targetListID")
    func processLocalMoveWithinSameParent() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Move r1 within f1 to index 1 (after r2)
        let editOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: "f1", index: 1))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let listMoveOp = ops.compactMap { op -> CRDTOperation.ListMove? in
            if case let .listMove(lm) = op.payload { return lm }
            return nil
        }.first

        #expect(listMoveOp != nil)
        #expect(listMoveOp?.sourceListID == listMoveOp?.targetListID)
    }

    @Test("processLocalMove to beginning sets afterPositionID to nil")
    func processLocalMoveToBeginning() {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Move r2 to index 0 within f1 (before r1)
        let editOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "r2", newParentID: "f1", index: 0))
        let ops = crdt.processLocal(operation: editOp, document: doc)

        let listMoveOp = ops.compactMap { op -> CRDTOperation.ListMove? in
            if case let .listMove(lm) = op.payload { return lm }
            return nil
        }.first

        #expect(listMoveOp != nil)
        #expect(listMoveOp?.afterPositionID == nil, "Moving to index 0 should have nil afterPositionID")
    }

    // MARK: - Helpers

    private func findPositionID(for nodeID: String, in listID: String, crdt: CRDTDocument) throws -> PositionID {
        let list = try #require(crdt.childrenLists[listID])
        let entry = try #require(list.entries.first(where: { $0.value == nodeID }))
        return entry.positionID
    }

    private func makeRemoteListMoveOp(
        sourceListID: String,
        targetListID: String,
        positionID: PositionID,
        afterPositionID: PositionID? = nil
    ) -> CRDTOperation {
        CRDTOperation(
            id: Timestamp(time: 101, peerID: peerB),
            dependencies: VectorClock(),
            payload: .listMove(CRDTOperation.ListMove(
                sourceListID: sourceListID,
                targetListID: targetListID,
                positionID: positionID,
                afterPositionID: afterPositionID,
                newPositionTimestamp: Timestamp(time: 100, peerID: peerB)
            ))
        )
    }

    // MARK: - Step 3: processRemoteListMove

    @Test("processRemoteListMove inserts actual node ID into target and tombstones source")
    func processRemoteListMoveInsertsIntoTarget() throws {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        // Move r1 from f1 to root via a remote listMove op
        let sourceListID = "f1"
        let positionID = try findPositionID(for: "r1", in: sourceListID, crdt: crdt)
        let listMoveOp = makeRemoteListMoveOp(
            sourceListID: sourceListID,
            targetListID: CRDTDocument.rootListID,
            positionID: positionID
        )

        let mutations = crdt.processRemote(operation: listMoveOp, document: doc)
        #expect(mutations != nil)

        // r1 should be in root list and tombstoned in f1
        let rootElements = crdt.childrenLists[CRDTDocument.rootListID]?.elements ?? []
        #expect(rootElements.contains("r1"), "r1 should appear in root list")

        let f1Elements = crdt.childrenLists["f1"]?.elements ?? []
        #expect(!f1Elements.contains("r1"), "r1 should be tombstoned in f1")
    }

    @Test("processRemoteListMove looks up actual element value, not placeholder")
    func processRemoteListMoveLooksUpElement() throws {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let positionID = try findPositionID(for: "r1", in: "f1", crdt: crdt)
        let listMoveOp = makeRemoteListMoveOp(
            sourceListID: "f1",
            targetListID: CRDTDocument.rootListID,
            positionID: positionID
        )

        _ = crdt.processRemote(operation: listMoveOp, document: doc)

        // Verify the element in root is "r1", not "moved" or any placeholder
        let rootElements = crdt.childrenLists[CRDTDocument.rootListID]?.elements ?? []
        #expect(rootElements.contains("r1"))
        #expect(!rootElements.contains("moved"))
    }

    @Test("processRemoteListMove to empty target creates list")
    func processRemoteListMoveToEmptyTarget() throws {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let positionID = try findPositionID(for: "r1", in: "f1", crdt: crdt)
        let listMoveOp = makeRemoteListMoveOp(
            sourceListID: "f1",
            targetListID: "newParent",
            positionID: positionID
        )

        _ = crdt.processRemote(operation: listMoveOp, document: doc)

        let targetElements = crdt.childrenLists["newParent"]?.elements ?? []
        #expect(targetElements == ["r1"])
    }

    @Test("processRemoteListMove with nil afterPositionID inserts at beginning")
    func processRemoteListMoveNilAfterPosition() throws {
        let doc = makeDoc()
        let crdt = CRDTDocument(peerID: peerA, document: doc)

        let positionID = try findPositionID(for: "r1", in: "f1", crdt: crdt)
        let listMoveOp = makeRemoteListMoveOp(
            sourceListID: "f1",
            targetListID: CRDTDocument.rootListID,
            positionID: positionID
        )

        _ = crdt.processRemote(operation: listMoveOp, document: doc)

        let rootElements = crdt.childrenLists[CRDTDocument.rootListID]?.elements ?? []
        // r1 should be at the beginning (before f1) since afterPositionID is nil
        #expect(rootElements.first == "r1", "r1 should be first in root when afterPositionID is nil")
    }
}
