//
//  EditOperationDeleteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationDeleteTests {
    // MARK: - Helpers

    private func makeDocWithFrame() -> EditableDocument {
        let c1 = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let c2 = PenNode(id: "c2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [c1, c2]))
        )
        let r1 = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        return EditableDocument(from: PenDocument(children: [frame, r1]))
    }

    // MARK: - Delete leaf

    @Test("Delete leaf node from root")
    func deleteLeafFromRoot() throws {
        let editable = makeDocWithFrame()
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "r1")))

        #expect(editable.nodes["r1"] == nil)
        #expect(editable.rootOrder == ["f1"])
    }

    @Test("Delete leaf node from parent updates children list")
    func deleteLeafFromParent() throws {
        let editable = makeDocWithFrame()
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "c1")))

        #expect(editable.nodes["c1"] == nil)
        #expect(editable.childIDs(of: "f1") == ["c2"])
        #expect(editable.parentID(of: "c1") == nil)
    }

    // MARK: - Delete subtree

    @Test("Delete frame with children cascades to all descendants")
    func deleteSubtree() throws {
        let editable = makeDocWithFrame()
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "f1")))

        #expect(editable.nodes["f1"] == nil)
        #expect(editable.nodes["c1"] == nil)
        #expect(editable.nodes["c2"] == nil)
        #expect(editable.rootOrder == ["r1"])
        #expect(editable.children["f1"] == nil)
    }

    @Test("Delete deeply nested subtree")
    func deleteDeepSubtree() throws {
        let text = PenNode(id: "t1", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let inner = PenNode(
            id: "f2",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [text]))
        )
        let outer = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [inner]))
        )
        let editable = EditableDocument(from: PenDocument(children: [outer]))

        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "f2")))

        #expect(editable.nodes["f2"] == nil)
        #expect(editable.nodes["t1"] == nil)
        #expect(editable.childIDs(of: "f1") == [])
        #expect(editable.nodes.count == 1) // only f1 remains
    }

    // MARK: - Error cases

    @Test("Reject delete of unknown ID")
    func rejectDeleteUnknown() throws {
        let editable = makeDocWithFrame()

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "missing")))
        }
    }
}
