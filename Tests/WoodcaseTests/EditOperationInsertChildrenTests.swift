//
//  EditOperationInsertChildrenTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An insert has to keep the difference between a container that declares no children
/// and one that declares an empty list, the way a replace already does: a node written
/// with `"children": []` reads back that way, and an undo restores the bytes the file
/// had rather than merely an equivalent tree.
@MainActor
@Suite("insert keeps a declared children array")
struct EditOperationInsertChildrenTests {
    /// A frame declaring an empty children array.
    private func emptyFrame(id: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: "Empty"),
            kind: .frame(PenNode.FrameData(children: []))
        )
    }

    /// A frame declaring no children array at all.
    private func silentFrame(id: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: "Silent"),
            kind: .frame(PenNode.FrameData())
        )
    }

    // MARK: - Insert

    @Test("A root inserted with an empty children array reads back with one")
    func rootInsertKeepsAnEmptyChildrenArray() throws {
        let document = EditableDocument(from: PenDocument(children: []))
        let node = emptyFrame(id: "emp01")

        try document.apply(.insertNode(EditOperation.InsertNode(node: node)))

        #expect(document.materialize().children == [node])
    }

    @Test("A container inserted with no children array reads back without one")
    func rootInsertKeepsAnAbsentChildrenArray() throws {
        let document = EditableDocument(from: PenDocument(children: []))
        let node = silentFrame(id: "sil01")

        try document.apply(.insertNode(EditOperation.InsertNode(node: node)))

        #expect(document.materialize().children == [node])
    }

    @Test("An empty container nested inside an inserted subtree keeps its array")
    func nestedInsertKeepsAnEmptyChildrenArray() throws {
        let document = EditableDocument(from: PenDocument(children: []))
        let subtree = PenNode(
            id: "out01",
            common: PenNodeCommon(name: "Outer"),
            kind: .frame(PenNode.FrameData(children: [emptyFrame(id: "emp01")]))
        )

        try document.apply(.insertNode(EditOperation.InsertNode(node: subtree)))

        #expect(document.materialize().children == [subtree])
    }

    // MARK: - Undo of a delete

    @Test("Undo of a delete restores an empty children array")
    func undoOfDeleteKeepsAnEmptyChildrenArray() throws {
        let node = emptyFrame(id: "emp01")
        let document = EditableDocument(from: PenDocument(children: [node]))
        let delete = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "emp01"))

        let inverse = try document.prepareInverse(of: delete)
        try document.apply(delete)
        for step in inverse {
            try document.apply(step)
        }

        #expect(document.materialize().children == [node])
    }

    @Test("Undo of a delete leaves an absent children array absent")
    func undoOfDeleteKeepsAnAbsentChildrenArray() throws {
        let node = silentFrame(id: "sil01")
        let document = EditableDocument(from: PenDocument(children: [node]))
        let delete = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "sil01"))

        let inverse = try document.prepareInverse(of: delete)
        try document.apply(delete)
        for step in inverse {
            try document.apply(step)
        }

        #expect(document.materialize().children == [node])
    }
}
