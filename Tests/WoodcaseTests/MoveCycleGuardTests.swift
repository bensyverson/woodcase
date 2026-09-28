//
//  MoveCycleGuardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Regression pins for the cycle guard on ``EditOperation/moveNode(_:)``.
///
/// `EditOperationMoveTests` covers the one-level case (moving a parent into its own
/// child). These pin the two remaining shapes: a deeper descendant, and the node itself.
@MainActor
struct MoveCycleGuardTests {
    /// `outer > middle > inner`, plus a sibling at root.
    private func makeEditable() -> EditableDocument {
        let inner = PenNode(
            id: "inner",
            common: PenNodeCommon(name: "Inner"),
            kind: .frame(PenNode.FrameData())
        )
        let middle = PenNode(
            id: "middle",
            common: PenNodeCommon(name: "Middle"),
            kind: .frame(PenNode.FrameData(children: [inner]))
        )
        let outer = PenNode(
            id: "outer",
            common: PenNodeCommon(name: "Outer"),
            kind: .frame(PenNode.FrameData(children: [middle]))
        )
        let sibling = PenNode(
            id: "sib",
            common: PenNodeCommon(name: "Sibling"),
            kind: .frame(PenNode.FrameData())
        )
        return EditableDocument(from: PenDocument(children: [outer, sibling]))
    }

    @Test("Moving a node under its own grandchild is refused")
    func moveUnderOwnDescendant() {
        let editable = makeEditable()

        #expect(throws: EditingError.wouldCreateCycle(nodeID: "outer", targetParentID: "inner")) {
            try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "outer", newParentID: "inner")))
        }

        #expect(editable.rootOrder == ["outer", "sib"])
        #expect(editable.childIDs(of: "outer") == ["middle"])
        #expect(editable.childIDs(of: "middle") == ["inner"])
    }

    @Test("Moving a node onto itself is refused")
    func moveOntoSelf() {
        let editable = makeEditable()

        #expect(throws: EditingError.wouldCreateCycle(nodeID: "middle", targetParentID: "middle")) {
            try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "middle", newParentID: "middle")))
        }

        #expect(editable.parentID(of: "middle") == "outer")
        #expect(editable.childIDs(of: "middle") == ["inner"])
    }

    @Test("Moving a node to an unrelated parent is still allowed")
    func moveToUnrelatedParent() throws {
        let editable = makeEditable()
        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "middle", newParentID: "sib")))

        #expect(editable.parentID(of: "middle") == "sib")
        #expect(editable.childIDs(of: "outer").isEmpty)
    }
}
