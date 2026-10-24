//
//  EditPlannerMoveRunTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Several stored nodes moved as one run
/// (``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)``): the
/// index counts the new parent's children with the moving nodes taken out, as a slot's
/// does, so the nodes land side by side in the order given wherever they came from
/// (leaf 14SEVW).
@MainActor
struct EditPlannerMoveRunTests {
    /// `Stack`, a vertical stack, holds `A`–`E`; `Other`, another, holds `X` and `Y`.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Stack", "x": 0, "y": 0, "width": 100, "height": "fit_content",
          "layout": "vertical", "children": [
          { "type": "rectangle", "id": "A", "width": 10, "height": 10 },
          { "type": "rectangle", "id": "B", "width": 10, "height": 10 },
          { "type": "rectangle", "id": "C", "width": 10, "height": 10 },
          { "type": "rectangle", "id": "D", "width": 10, "height": 10 },
          { "type": "rectangle", "id": "E", "width": 10, "height": 10 }
        ] },
        { "type": "frame", "id": "Other", "x": 200, "y": 0, "width": 100, "height": "fit_content",
          "layout": "vertical", "children": [
          { "type": "rectangle", "id": "X", "width": 10, "height": 10 },
          { "type": "rectangle", "id": "Y", "width": 10, "height": 10 }
        ] },
        { "type": "rectangle", "id": "R", "x": 400, "y": 0, "width": 10, "height": 10 }
      ]
    }
    """

    /// Plans the move of `ids` into `parent` at `index`, applies it, and returns the plan.
    @discardableResult
    private func move(
        _ ids: [String], into parent: String?, at index: Int?, in document: EditableDocument
    ) throws -> StructuralEditPlan {
        let plan = try EditPlanner.planMove(
            nodeIDs: ids, into: parent, at: index, in: document, layout: WrapFixture.layout(of: document)
        )
        try WrapFixture.apply(plan.operations, to: document)
        return plan
    }

    @Test("A run moved forward in its own stack lands together, the index counted with it taken out")
    func forwardRun() throws {
        let document = try WrapFixture.document(Self.json)
        // After D: index 2 of [C, D, E].
        let plan = try move(["A", "B"], into: "Stack", at: 2, in: document)
        #expect(document.childIDs(of: "Stack") == ["C", "D", "A", "B", "E"])
        #expect(plan.placedIDs == ["A", "B"])
    }

    @Test("A run moved backward in its own stack lands together")
    func backwardRun() throws {
        let document = try WrapFixture.document(Self.json)
        // Before B: index 1 of [A, B, C].
        try move(["D", "E"], into: "Stack", at: 1, in: document)
        #expect(document.childIDs(of: "Stack") == ["A", "D", "E", "B", "C"])
    }

    @Test("Nodes with gaps between them gather where they land, in the order given")
    func nonContiguous() throws {
        let document = try WrapFixture.document(Self.json)
        // Before E: index 2 of [B, D, E].
        try move(["A", "C"], into: "Stack", at: 2, in: document)
        #expect(document.childIDs(of: "Stack") == ["B", "D", "A", "C", "E"])
    }

    @Test("A run moved to the end of its own stack lands there, together")
    func indexAtEnd() throws {
        let document = try WrapFixture.document(Self.json)
        // Past the last of [C, D, E].
        try move(["A", "B"], into: "Stack", at: 3, in: document)
        #expect(document.childIDs(of: "Stack") == ["C", "D", "E", "A", "B"])
    }

    @Test("Nodes from two parents land together, the index counted without the ones already there")
    func mixedParents() throws {
        let document = try WrapFixture.document(Self.json)
        // Before D: index 2 of [B, C, D, E].
        try move(["X", "A"], into: "Stack", at: 2, in: document)
        #expect(document.childIDs(of: "Stack") == ["B", "C", "X", "A", "D", "E"])
        #expect(document.childIDs(of: "Other") == ["Y"])
    }

    @Test("Nodes from another parent can land at the end of a stack by its index")
    func fromElsewhereToEnd() throws {
        let document = try WrapFixture.document(Self.json)
        try move(["X", "Y"], into: "Stack", at: 5, in: document)
        #expect(document.childIDs(of: "Stack") == ["A", "B", "C", "D", "E", "X", "Y"])
        #expect(document.childIDs(of: "Other").isEmpty)
    }

    @Test("A run moved forward among the top-level nodes lands together")
    func topLevelRun() throws {
        let document = try WrapFixture.document(Self.json)
        // After R: index 1 of [R].
        try move(["Stack", "Other"], into: nil, at: 1, in: document)
        #expect(document.rootOrder == ["R", "Stack", "Other"])
    }

    @Test("An index past the children left once the run is taken out is refused")
    func indexPastEnd() throws {
        let document = try WrapFixture.document(Self.json)
        #expect(throws: EditRefusal.self) {
            try EditPlanner.planMove(
                nodeIDs: ["A", "B"], into: "Stack", at: 4, in: document, layout: WrapFixture.layout(of: document)
            )
        }
    }

    @Test("Slot content and a stored node moved forward into a stored stack land together")
    func slotContentAndStored() throws {
        let document = try SlotScreenFixture.document()
        let rectangles = ["S2", "S3"].map { id in
            PenNode(id: id, common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20))))
        }
        let insert = try EditPlanner.planInsert(rectangles, into: "Stack", in: document)
        try SlotScreenFixture.apply(insert.operations, to: document)
        #expect(document.childIDs(of: "Stack") == ["S1", "S2", "S3"])

        // Between S2 and S3: index 1 of [S2, S3].
        let plan = try EditPlanner.planMove(
            nodeIDs: ["Filled/Row1/ItemA", "S1"], into: "Stack", at: 1,
            in: document, layout: SlotScreenFixture.layout(of: document)
        )
        try SlotScreenFixture.apply(plan.operations, to: document)

        let row = try #require(plan.placedIDs.first)
        #expect(document.childIDs(of: "Stack") == ["S2", row, "S1", "S3"])
    }

    @Test("A run moved forward is undone as one edit")
    func undoneAsOne() throws {
        let document = try WrapFixture.document(Self.json)
        let plan = try EditPlanner.planMove(
            nodeIDs: ["A", "B"], into: "Stack", at: 2, in: document, layout: WrapFixture.layout(of: document)
        )
        var inverse: [EditOperation] = []
        for operation in plan.operations {
            try inverse.insert(contentsOf: document.prepareInverse(of: operation), at: 0)
            try document.apply(operation)
        }
        #expect(document.childIDs(of: "Stack") == ["C", "D", "A", "B", "E"])
        try WrapFixture.apply(inverse, to: document)
        #expect(document.childIDs(of: "Stack") == ["A", "B", "C", "D", "E"])
    }
}
