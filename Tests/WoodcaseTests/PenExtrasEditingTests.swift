//
//  PenExtrasEditingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers ``PenExtras`` through the editing layer: the flat store keeps them, an edit
/// of another property keeps them, a copy carries them, a replace drops them, an
/// inverse restores them, revisions see them, and a CRDT peer converges on them.
@MainActor
struct PenExtrasEditingTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    // MARK: - Helpers

    private func fixture() throws -> PenDocument {
        try PenExtrasDecodingTests.fixture()
    }

    private func editable() throws -> EditableDocument {
        try EditableDocument(from: fixture())
    }

    private func setProperties(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    /// The fill array a node holds, as the .pen file writes it.
    private func fills(of node: PenNode) throws -> AnyCodable {
        try NodePropertyCodec.value(at: "kind.fills", of: node)
    }

    // MARK: - Flat store

    @Test("materialize writes back root and node extras unchanged")
    func materializeRoundTrips() throws {
        let document = try fixture()
        #expect(try EditableDocument(from: document).materialize() == document)
    }

    @Test("Root extras live on the editable document")
    func rootExtrasOnEditableDocument() throws {
        #expect(try editable().extras["futureRootKey"] == ["a": 1])
    }

    @Test("Setting another property keeps node, fill, stroke and effect extras")
    func setKeepsExtras() throws {
        let document = try editable()
        let before = try #require(document.node(id: "Board"))

        try document.apply(setProperties("Board", ["kind.width": 410, "common.name": "Renamed"]))

        let after = try #require(document.node(id: "Board"))
        #expect(after.extras == before.extras)
        #expect(try NodePropertyCodec.value(at: "kind.fills", of: after) == fills(of: before))
        #expect(try NodePropertyCodec.value(at: "kind.stroke", of: after)
            == NodePropertyCodec.value(at: "kind.stroke", of: before))
        #expect(try NodePropertyCodec.value(at: "kind.effects", of: after)
            == NodePropertyCodec.value(at: "kind.effects", of: before))
    }

    @Test("Reading kind.fills and writing it straight back is a no-op, extras included")
    func fillsReadWriteIsANoOp() throws {
        let node = try #require(try editable().node(id: "Board"))
        let patched = try NodePropertyCodec.setting(fills(of: node), at: "kind.fills", on: node)
        #expect(patched == node)
    }

    @Test("A copy with fresh ids carries every extra")
    func copyCarriesExtras() throws {
        let board = try editable().materializeSubtree(rootID: "Board")
        let (copy, _) = PenID.remapIDs(in: board)
        #expect(copy.id != board.id)
        #expect(copy.extras == board.extras)
        #expect(try fills(of: copy) == fills(of: board))
        #expect(copy.kind.inlineChildren.map(\.extras) == board.kind.inlineChildren.map(\.extras))
    }

    @Test("A replace takes the replacement's extras, which authored input never has")
    func replaceDropsExtras() throws {
        let document = try editable()
        let replacement = PenNode(id: "Card1", common: PenNodeCommon(name: "Card"), kind: .rectangle(PenNode.RectangleData()))

        try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(node: replacement)))

        #expect(try #require(document.node(id: "Card1")).extras.isEmpty)
    }

    @Test("The inverse of a delete reinserts the node with its extras")
    func deleteInverseRestoresExtras() throws {
        let document = try editable()
        let before = try document.materializeSubtree(rootID: "Board")
        let delete = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "Board"))
        let inverse = try document.prepareInverse(of: delete)

        try document.apply(delete)
        for operation in inverse {
            try document.apply(operation)
        }

        #expect(try document.materializeSubtree(rootID: "Board") == before)
    }

    @Test("The inverse of a replace restores the replaced node's extras")
    func replaceInverseRestoresExtras() throws {
        let document = try editable()
        let before = try #require(document.node(id: "Card1"))
        let replace = EditOperation.replaceSubtree(EditOperation.ReplaceSubtree(
            node: PenNode(id: "Card1", common: PenNodeCommon(name: "Card"), kind: .rectangle(PenNode.RectangleData()))
        ))
        let inverse = try document.prepareInverse(of: replace)

        try document.apply(replace)
        for operation in inverse {
            try document.apply(operation)
        }

        #expect(try #require(document.node(id: "Card1")) == before)
    }

    @Test("An instance child's override with an unknown key expands onto the child as an extra")
    func overrideUnknownKeyExpands() throws {
        let document = try editable()
        let expanded = try document.expandRef(nodeID: "Inst1").expandedNode
        let label = try #require(expanded.kind.inlineChildren.first)
        #expect(label.extras["futureOverrideKey"] == "o")
    }

    // MARK: - Revisions

    @Test("A node's revision covers its extras")
    func revisionCoversNodeExtras() throws {
        let plain = try editable()
        var document = try fixture()
        document.children[0].extras = PenExtras(["futureNodeKey": "changed"])
        let changed = EditableDocument(from: document)
        #expect(plain.revision(of: "Board") != changed.revision(of: "Board"))
    }

    @Test("The document revision covers root extras")
    func documentRevisionCoversRootExtras() throws {
        let plain = try editable()
        var document = try fixture()
        document.extras = PenExtras(["futureRootKey": "changed"])
        #expect(plain.documentRevision != EditableDocument(from: document).documentRevision)
    }

    // MARK: - CRDT

    @Test("A node inserted with extras reaches a peer with them")
    func crdtInsertCarriesExtras() throws {
        let document = try fixture()
        let a = EditableDocument(from: document, peerID: peerA)
        let b = EditableDocument(from: document, peerID: peerB)
        let (copy, _) = try PenID.remapIDs(in: a.materializeSubtree(rootID: "Board"))

        let ops = try a.applyLocal(.insertNode(EditOperation.InsertNode(node: copy, parentID: nil, index: nil)))
        let wire = try JSONDecoder().decode([CRDTOperation].self, from: JSONEncoder().encode(ops))
        b.applyRemote(wire)

        #expect(try b.materializeSubtree(rootID: copy.id) == a.materializeSubtree(rootID: copy.id))
        #expect(try #require(b.node(id: copy.id)).extras.values == ["futureNodeKey": ["nested": [1, 2]]])
    }

    @Test("A replace in collaborative mode clears extras on both peers")
    func crdtReplaceConvergesOnExtras() throws {
        let document = try fixture()
        let a = EditableDocument(from: document, peerID: peerA)
        let b = EditableDocument(from: document, peerID: peerB)
        let replacement = PenNode(id: "Card1", common: PenNodeCommon(name: "Card"), kind: .rectangle(PenNode.RectangleData()))

        let ops = try a.applyLocal(.replaceSubtree(EditOperation.ReplaceSubtree(node: replacement)))
        b.applyRemote(ops)

        #expect(try #require(a.node(id: "Card1")).extras.isEmpty)
        #expect(try #require(b.node(id: "Card1")).extras.isEmpty)
    }

    @Test("Extras are one last-writer-wins register per node in the CRDT")
    func crdtExtrasRegister() throws {
        let document = try fixture()
        let a = EditableDocument(from: document, peerID: peerA)
        let replacement = PenNode(id: "Card1", common: PenNodeCommon(name: "Card"), kind: .rectangle(PenNode.RectangleData()))

        _ = try a.applyLocal(.replaceSubtree(EditOperation.ReplaceSubtree(node: replacement)))

        let map = try #require(a.crdtDocument?.propertyMaps["Card1"])
        #expect(map.timestamps[CRDTDocument.extrasProperty] != nil)
    }
}
