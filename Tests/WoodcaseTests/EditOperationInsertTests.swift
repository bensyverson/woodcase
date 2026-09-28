//
//  EditOperationInsertTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationInsertTests {
    // MARK: - Helpers

    private func makeEmptyDocument() -> EditableDocument {
        EditableDocument(from: PenDocument(children: []))
    }

    private func makeDocWithFrame() -> EditableDocument {
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        return EditableDocument(from: PenDocument(children: [frame]))
    }

    // MARK: - Insert at root

    @Test("Insert at root appends to rootOrder")
    func insertAtRoot() throws {
        let editable = makeEmptyDocument()
        let node = PenNode(id: "n1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        try editable.apply(.insertNode(EditOperation.InsertNode(node: node)))

        #expect(editable.rootOrder == ["n1"])
        #expect(editable.nodes["n1"] != nil)
    }

    @Test("Insert at root at specific index")
    func insertAtRootIndex() throws {
        let editable = makeEmptyDocument()
        let n1 = PenNode(id: "n1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let n2 = PenNode(id: "n2", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let n3 = PenNode(id: "n3", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        try editable.apply(.insertNode(EditOperation.InsertNode(node: n1)))
        try editable.apply(.insertNode(EditOperation.InsertNode(node: n2)))
        try editable.apply(.insertNode(EditOperation.InsertNode(node: n3, index: 1)))

        #expect(editable.rootOrder == ["n1", "n3", "n2"])
    }

    // MARK: - Insert into container

    @Test("Insert into frame as child")
    func insertIntoFrame() throws {
        let editable = makeDocWithFrame()
        let node = PenNode(id: "c2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))

        try editable.apply(.insertNode(EditOperation.InsertNode(node: node, parentID: "f1")))

        #expect(editable.childIDs(of: "f1") == ["c1", "c2"])
        #expect(editable.parentID(of: "c2") == "f1")
    }

    @Test("Insert into group as child")
    func insertIntoGroup() throws {
        let group = PenNode(id: "g1", common: PenNodeCommon(), kind: .group(PenNode.GroupData()))
        let editable = EditableDocument(from: PenDocument(children: [group]))
        let node = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        try editable.apply(.insertNode(EditOperation.InsertNode(node: node, parentID: "g1")))

        #expect(editable.childIDs(of: "g1") == ["c1"])
        #expect(editable.parentID(of: "c1") == "g1")
    }

    // MARK: - Error cases

    @Test("Reject insert into text node (cannotHaveChildren)")
    func rejectInsertIntoLeaf() throws {
        let text = PenNode(id: "t1", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let editable = EditableDocument(from: PenDocument(children: [text]))
        let node = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        #expect(throws: EditingError.cannotHaveChildren(parentID: "t1")) {
            try editable.apply(.insertNode(EditOperation.InsertNode(node: node, parentID: "t1")))
        }
    }

    @Test("Reject duplicate node ID")
    func rejectDuplicateID() throws {
        let editable = makeDocWithFrame()
        let duplicate = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        #expect(throws: EditingError.duplicateNodeID(id: "c1")) {
            try editable.apply(.insertNode(EditOperation.InsertNode(node: duplicate)))
        }
    }

    @Test("Reject a subtree whose nodes duplicate each other's IDs")
    func rejectDuplicateIDWithinTheSubtree() throws {
        let editable = makeEmptyDocument()
        let leaf = PenNode(id: "dup", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let subtree = PenNode(
            id: "f9",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [leaf, leaf]))
        )

        #expect(throws: EditingError.duplicateNodeID(id: "dup")) {
            try editable.apply(.insertNode(EditOperation.InsertNode(node: subtree)))
        }
        #expect(editable.node(id: "f9") == nil)
    }

    @Test("Reject insert at out-of-bounds index")
    func rejectOutOfBoundsIndex() throws {
        let editable = makeEmptyDocument()
        let node = PenNode(id: "n1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        #expect(throws: EditingError.invalidIndex(index: 5, count: 0)) {
            try editable.apply(.insertNode(EditOperation.InsertNode(node: node, index: 5)))
        }
    }

    @Test("Reject insert into nonexistent parent")
    func rejectMissingParent() throws {
        let editable = makeEmptyDocument()
        let node = PenNode(id: "n1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        #expect(throws: EditingError.parentNotFound(id: "missing")) {
            try editable.apply(.insertNode(EditOperation.InsertNode(node: node, parentID: "missing")))
        }
    }

    // MARK: - Subtree insertion

    @Test("Insert node with children flattens subtree into store")
    func insertSubtree() throws {
        let editable = makeEmptyDocument()
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child]))
        )

        try editable.apply(.insertNode(EditOperation.InsertNode(node: frame)))

        #expect(editable.nodes.count == 2)
        #expect(editable.rootOrder == ["f1"])
        #expect(editable.childIDs(of: "f1") == ["c1"])
        #expect(editable.parentID(of: "c1") == "f1")
        // Frame stored with nil children
        if case let .frame(data) = editable.nodes["f1"]?.kind {
            #expect(data.children == nil)
        } else {
            Issue.record("Expected frame kind")
        }
    }
}
