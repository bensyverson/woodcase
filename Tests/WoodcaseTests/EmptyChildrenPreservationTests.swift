//
//  EmptyChildrenPreservationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A container that loses its last child keeps a declared `children: []` rather than
/// collapsing to no array at all — locally, through a detach, and on a CRDT peer —
/// so a document that removed every child materializes equal to a file that says so.
@MainActor
@Suite("Removing the last child keeps children: []")
struct EmptyChildrenPreservationTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    // MARK: - Helpers

    /// A box holding one child, an empty target frame, a component and an instance
    /// that is the only child of its holder.
    private func document() throws -> PenDocument {
        try PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "Box", "type": "frame", "children": [{"id": "Only", "type": "rectangle"}]},
          {"id": "Dest", "type": "frame"},
          {"id": "Comp", "type": "frame", "reusable": true, "children": [{"id": "Lbl", "type": "text"}]},
          {"id": "Holder", "type": "frame", "children": [{"id": "Inst", "type": "ref", "ref": "Comp"}]}
        ]}
        """#)
    }

    /// The node `id` in a materialized document's roots.
    private func root(_ id: String, in document: PenDocument) throws -> PenNode {
        try #require(document.children.first { $0.id == id })
    }

    // MARK: - Local edits

    @Test("Moving the last child out leaves an empty declared array behind")
    func moveKeepsEmptyChildren() throws {
        let editable = try EditableDocument(from: document())
        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "Only", newParentID: "Dest")))

        #expect(editable.children["Box"] == [])
        #expect(try root("Box", in: editable.materialize()).kind.declaredChildIDs == [])
    }

    @Test("Deleting the last child leaves an empty declared array behind")
    func deleteKeepsEmptyChildren() throws {
        let editable = try EditableDocument(from: document())
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Only")))

        #expect(try root("Box", in: editable.materialize()).kind.declaredChildIDs == [])
    }

    @Test("A detaching delete whose instance was the last child keeps the holder's array")
    func detachingDeleteKeepsEmptyChildren() throws {
        let editable = try EditableDocument(from: document())
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Comp", instances: .detach)))
        let holder = try root("Holder", in: editable.materialize())
        #expect(holder.kind.declaredChildIDs?.count == 1)

        let detachedRoot = try #require(editable.children["Holder"]?.first)
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: detachedRoot)))
        #expect(try root("Holder", in: editable.materialize()).kind.declaredChildIDs == [])
    }

    @Test("The materialized document equals one parsed from a file that declares the empty array")
    func materializeEqualsTheDeclaredFile() throws {
        let editable = try EditableDocument(from: document())
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Only")))

        let box = try root("Box", in: editable.materialize())
        let declared = try PenParser.parse(#"""
        {"version": "2.17", "children": [{"id": "Box", "type": "frame", "children": []}]}
        """#)
        #expect(box == declared.children.first)
    }

    // MARK: - CRDT

    @Test("A remote delete of the last child keeps the array on the peer, converging with the author")
    func remoteDeleteKeepsEmptyChildren() throws {
        let source = try document()
        let a = EditableDocument(from: source, peerID: peerA)
        let b = EditableDocument(from: source, peerID: peerB)

        let ops = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "Only")))
        b.applyRemote(ops)

        #expect(try root("Box", in: a.materialize()).kind.declaredChildIDs == [])
        #expect(b.materialize() == a.materialize())
    }

    @Test("A remote move of the last child keeps the array on the peer, converging with the author")
    func remoteMoveKeepsEmptyChildren() throws {
        let source = try document()
        let a = EditableDocument(from: source, peerID: peerA)
        let b = EditableDocument(from: source, peerID: peerB)

        let ops = try a.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "Only", newParentID: "Dest")))
        b.applyRemote(ops)

        #expect(try root("Box", in: a.materialize()).kind.declaredChildIDs == [])
        #expect(b.materialize() == a.materialize())
    }

    @Test("A container that never declared children is not given an array by a remote edit")
    func remoteEditLeavesUndeclaredAlone() throws {
        let source = try document()
        let a = EditableDocument(from: source, peerID: peerA)
        let b = EditableDocument(from: source, peerID: peerB)

        let ops = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "Only")))
        b.applyRemote(ops)

        #expect(try root("Dest", in: b.materialize()).kind.declaredChildIDs == nil)
    }
}
