//
//  EditOperationMoveTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationMoveTests {
    // MARK: - Helpers

    /// frame(f1) > [rect(c1)], frame(f2) > [text(c2)]
    private func makeTwoFrameDoc() -> EditableDocument {
        let c1 = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let f1 = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [c1]))
        )
        let c2 = PenNode(id: "c2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let f2 = PenNode(
            id: "f2",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [c2]))
        )
        return EditableDocument(from: PenDocument(children: [f1, f2]))
    }

    // MARK: - Move between parents

    @Test("Move node from one parent to another")
    func moveBetweenParents() throws {
        let editable = makeTwoFrameDoc()
        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: "f2")))

        #expect(editable.childIDs(of: "f1") == [])
        #expect(editable.childIDs(of: "f2") == ["c2", "c1"])
        #expect(editable.parentID(of: "c1") == "f2")
    }

    @Test("Move node to root from a parent")
    func moveToRoot() throws {
        let editable = makeTwoFrameDoc()
        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: nil)))

        #expect(editable.childIDs(of: "f1") == [])
        #expect(editable.rootOrder == ["f1", "f2", "c1"])
        #expect(editable.parentID(of: "c1") == nil)
    }

    @Test("Move node from root to a parent")
    func moveFromRoot() throws {
        let editable = makeTwoFrameDoc()
        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "f2", newParentID: "f1")))

        #expect(editable.rootOrder == ["f1"])
        #expect(editable.childIDs(of: "f1") == ["c1", "f2"])
        #expect(editable.parentID(of: "f2") == "f1")
    }

    @Test("Reorder within same parent")
    func reorderWithinParent() throws {
        let c1 = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let c2 = PenNode(id: "c2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let c3 = PenNode(id: "c3", common: PenNodeCommon(), kind: .ellipse(PenNode.EllipseData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [c1, c2, c3]))
        )
        let editable = EditableDocument(from: PenDocument(children: [frame]))

        // Move c3 to index 0
        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "c3", newParentID: "f1", index: 0)))

        #expect(editable.childIDs(of: "f1") == ["c3", "c1", "c2"])
    }

    // MARK: - Error cases

    @Test("Reject move that would create cycle")
    func rejectCycle() throws {
        // f1 > f2 > t1 — trying to move f1 into f2 would create a cycle
        let t1 = PenNode(id: "t1", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let f2 = PenNode(
            id: "f2",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [t1]))
        )
        let f1 = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [f2]))
        )
        let editable = EditableDocument(from: PenDocument(children: [f1]))

        #expect(throws: EditingError.wouldCreateCycle(nodeID: "f1", targetParentID: "f2")) {
            try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "f1", newParentID: "f2")))
        }
    }

    @Test("Reject move into non-container node")
    func rejectMoveIntoLeaf() throws {
        let editable = makeTwoFrameDoc()

        #expect(throws: EditingError.cannotHaveChildren(parentID: "c1")) {
            try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "c1")))
        }
    }

    @Test("Reject move of unknown node ID")
    func rejectMoveUnknown() throws {
        let editable = makeTwoFrameDoc()

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "missing", newParentID: "f1")))
        }
    }
}
