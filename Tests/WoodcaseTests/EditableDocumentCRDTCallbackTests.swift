//
//  EditableDocumentCRDTCallbackTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditableDocumentCRDTCallbackTests {
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

    /// Creates two peer documents and returns a remote operation from peer B.
    private func makeRemoteOp() throws -> (EditableDocument, CRDTOperation) {
        let docA = EditableDocument(from: makeDoc(), peerID: peerA)
        let docB = EditableDocument(from: makeDoc(), peerID: peerB)

        // Peer B makes a local edit
        let newNode = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "New"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let ops = try docB.applyLocal(.insertNode(
            EditOperation.InsertNode(node: newNode, parentID: "f1")
        ))
        #expect(!ops.isEmpty)
        return (docA, ops[0])
    }

    // MARK: - onRemoteChange fires after single applyRemote

    @Test("onRemoteChange fires after applyRemote (single op)")
    func onRemoteChangeFiersAfterSingleApplyRemote() throws {
        let (docA, op) = try makeRemoteOp()

        var callCount = 0
        docA.onRemoteChange = {
            callCount += 1
        }

        docA.applyRemote(op)
        #expect(callCount == 1)
    }

    // MARK: - onRemoteChange fires once for batch

    @Test("onRemoteChange fires once after applyRemote (batch)")
    func onRemoteChangeFiresOnceForBatch() throws {
        let docA = EditableDocument(from: makeDoc(), peerID: peerA)
        let docB = EditableDocument(from: makeDoc(), peerID: peerB)

        // Generate two remote ops from peer B
        let node1 = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "New1"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let node2 = PenNode(
            id: "n2",
            common: PenNodeCommon(name: "New2"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let ops1 = try docB.applyLocal(.insertNode(
            EditOperation.InsertNode(node: node1, parentID: "f1")
        ))
        let ops2 = try docB.applyLocal(.insertNode(
            EditOperation.InsertNode(node: node2, parentID: "f1")
        ))
        let allOps = ops1 + ops2

        var callCount = 0
        docA.onRemoteChange = {
            callCount += 1
        }

        docA.applyRemote(allOps)
        #expect(callCount == 1, "Batch applyRemote should fire onRemoteChange exactly once")
    }

    // MARK: - onRemoteChange does NOT fire for local edits

    @Test("onRemoteChange does NOT fire after applyLocal")
    func onRemoteChangeDoesNotFireForLocal() throws {
        let doc = EditableDocument(from: makeDoc(), peerID: peerA)

        var callCount = 0
        doc.onRemoteChange = {
            callCount += 1
        }

        let newNode = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "New"),
            kind: .rectangle(PenNode.RectangleData())
        )
        _ = try doc.applyLocal(.insertNode(
            EditOperation.InsertNode(node: newNode, parentID: "f1")
        ))

        #expect(callCount == 0, "Local edits should not trigger onRemoteChange")
    }

    // MARK: - Dirty nodes correct when callback fires

    @Test("dirtyNodeIDs contains mutated node when onRemoteChange fires")
    func dirtyNodesCorrectWhenCallbackFires() throws {
        let (docA, op) = try makeRemoteOp()

        // Prime the layout cache so dirty tracking works
        docA.computeLayout()

        var capturedDirtyIDs: Set<String>?
        docA.onRemoteChange = {
            capturedDirtyIDs = docA.dirtyNodeIDs
        }

        docA.applyRemote(op)
        #expect(capturedDirtyIDs != nil)
        // The inserted node "n1" is new, which triggers a full layout invalidation
        // (new node via CRDT → _layoutCache.invalidateAll()). The dirty set should
        // be non-empty, reflecting that re-layout is needed.
        #expect(capturedDirtyIDs?.isEmpty == false)
    }
}
