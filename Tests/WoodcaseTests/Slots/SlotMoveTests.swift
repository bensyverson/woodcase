//
//  SlotMoveTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Moves into, within and out of an instance's slot
/// (``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)``), each
/// written as one `children` override of the slot (Penumbra spec §13.5 rules 4–7).
@MainActor
struct SlotMoveTests {
    // MARK: - Helpers

    private func move(
        _ ids: [String], into parent: String?, at index: Int? = nil,
        keeping offset: PenPoint? = nil, in doc: EditableDocument
    ) throws(EditRefusal) -> StructuralEditPlan {
        try EditPlanner.planMove(
            nodeIDs: ids, into: parent, at: index, keepingDrawnPlace: offset,
            in: doc, layout: SlotScreenFixture.layout(of: doc)
        )
    }

    /// The `children` overrides among a plan's operations, as (ref, key).
    private func childrenWrites(_ plan: StructuralEditPlan) -> [String] {
        plan.operations.compactMap { operation in
            guard case let .overrideDescendant(op) = operation, op.properties["children"] != nil else { return nil }
            return "\(op.refNodeID)|\(op.descendantID)"
        }
    }

    // MARK: - Within a slot

    @Test("Reordering a fill writes one children override with the new order")
    func reorderWithinAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Filled/Row3/ItemA"], into: "Filled/List", at: 0, in: doc)

        #expect(plan.operations.count == 1)
        #expect(childrenWrites(plan) == ["Filled|List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row3", "Row1", "Row2"])
        #expect(plan.placedIDs == ["Filled/Row3/ItemA"])
        #expect(SlotScreenFixture.expandedChildren(of: "Filled/List", in: doc)
            == ["Filled/Row3/ItemA", "Filled/Row1/ItemA", "Filled/Row2/ItemB"])
    }

    @Test("A moved node keeps its own overrides in the fill")
    func reorderKeepsTheNodesOwnValues() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Filled/Row2/ItemB"], into: "Filled/List", at: nil, in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row3", "Row2"])
        let rows = try TreeView.rows(of: doc, root: "Filled", expandInstances: true, properties: ["kind.content"])
        #expect(rows.first { $0.id == "Filled/Row2/BLbl" }?.properties?["kind.content"] == .string("Second"))
    }

    // MARK: - Into a slot

    @Test("A node dragged into a slot leaves its old parent and joins the fill, in one edit")
    func intoAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Loose"], into: "Filled/List", at: 1, in: doc)

        #expect(childrenWrites(plan) == ["Filled|List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(doc.node(id: "Loose") == nil)
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Loose", "Row2", "Row3"])
        #expect(plan.placedIDs == ["Filled/Loose"])
        #expect(SlotScreenFixture.expandedChildren(of: "Filled/List", in: doc)?.contains("Filled/Loose") == true)
    }

    @Test("A node dropped into a free slot keeps its drawn place")
    func intoAFreeSlotKeepsPlace() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Loose"], into: "FreeInst/Area", keeping: PenPoint(x: 0, y: 0), in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let layout = SlotScreenFixture.layout(of: doc)
        let rect = try #require(PenLayoutEngine.canvasPlacement(
            of: "FreeInst/Loose", in: layout.document, layoutRects: layout.rects
        )?.corners.first)
        #expect(abs(rect.x - 10) < 1e-6)
        #expect(abs(rect.y - 510) < 1e-6)
    }

    @Test("Several nodes from two places land together in one slot, each slot written once")
    func severalIntoOneSlot() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Filled/Row1/ItemA", "Loose", "Filled/Row3/ItemA"], into: "Emptied/List", in: doc)

        #expect(Set(childrenWrites(plan)) == ["Filled|List", "Emptied|List"])
        #expect(childrenWrites(plan).count == 2)
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.fillIDs("List", of: "Emptied", in: doc) == ["Row1", "Loose", "Row3"])
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row2"])
        #expect(plan.placedIDs == ["Emptied/Row1/ItemA", "Emptied/Loose", "Emptied/Row3/ItemA"])
    }

    @Test("A nested instance's slot is written on the outermost instance, by the path to it")
    func intoANestedInstancesSlot() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Loose"], into: "PanelInst/PScr/List", at: 0, in: doc)

        #expect(childrenWrites(plan) == ["PanelInst|PScr/List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.expandedChildren(of: "PanelInst/PScr/List", in: doc)?.first == "PanelInst/PScr/Loose")
        #expect(plan.placedIDs == ["PanelInst/PScr/Loose"])
    }

    @Test("A slot of an instance inside a fill is written inside that fill, as one override")
    func intoASlotInsideAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Loose"], into: "HostInst/Nest/List", in: doc)

        #expect(childrenWrites(plan) == ["HostInst|Body"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.expandedChildren(of: "HostInst/Nest/List", in: doc)
            == ["HostInst/Nest/NRow1/ItemA", "HostInst/Nest/Loose"])
        #expect(doc.slot("HostInst/Nest/List")?.contentIDs == ["HostInst/Nest/NRow1/ItemA", "HostInst/Nest/Loose"])
    }

    // MARK: - Out of a slot

    @Test("A node dragged out of a slot becomes an ordinary node, its own values kept")
    func outOfAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Filled/Row2/ItemB"], into: "Board", in: doc)

        #expect(childrenWrites(plan) == ["Filled|List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row3"])
        #expect(doc.parentID(of: "Row2") == "Board")
        guard case let .ref(data)? = doc.node(id: "Row2")?.kind else { Issue.record("not a ref"); return }
        #expect(data.descendants?["BLbl"]?.properties["content"] == .string("Second"))
        #expect(plan.placedIDs == ["Row2"], "a stored instance is selected by its own id")
    }

    @Test("A node dragged out of a free slot keeps its drawn place")
    func outOfAFreeSlotKeepsPlace() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["FreeInst/Dot"], into: "Board", keeping: PenPoint(x: 0, y: 0), in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.node(id: "Dot")?.common.x?.literalValue == 425)
        #expect(doc.node(id: "Dot")?.common.y?.literalValue == 1036)
    }

    // MARK: - Default content

    @Test("The first change on default content copies it into a fill, overrides folded in, then applies the change")
    func firstChangeCopiesTheDefault() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Loose"], into: "Default/List", at: 0, in: doc)

        #expect(childrenWrites(plan) == ["Default|List"])
        #expect(plan.materializedSlotIDs == ["Default/List"])
        let renamed = plan.renamed("Default/Empty1/EmptyState")
        #expect(renamed != "Default/Empty1/EmptyState")
        #expect(renamed.hasPrefix("Default/"))
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.slot("Default/List")?.state == .filled)
        #expect(doc.slot("Default/List")?.contentIDs == ["Default/Loose", renamed])
        // The old key on the default content is gone; the message lives in the copy.
        #expect(SlotScreenFixture.entry("Empty1/ETxt", of: "Default", in: doc) == nil)
        let copy = renamed.split(separator: "/").map(String.init)[1]
        let rows = try TreeView.rows(of: doc, root: "Default", expandInstances: true, properties: ["kind.content"])
        #expect(rows.first { $0.id == "Default/\(copy)/ETxt" }?.properties?["kind.content"] == .string("Nothing yet"))
    }

    @Test("Reordering default content copies it first; the copies take fresh ids")
    func reorderDefaultContent() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try move(["Default/Empty1/EmptyState"], into: "Default/List", at: 0, in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let ids = try #require(SlotScreenFixture.fillIDs("List", of: "Default", in: doc))
        #expect(ids.count == 1)
        #expect(ids != ["Empty1"])
        #expect(plan.placedIDs == [plan.renamed("Default/Empty1/EmptyState")])
    }

    // MARK: - Refusals

    @Test("An instance's own nodes are still refused, as are targets outside its slots")
    func refusalsOutsideSlots() throws {
        let doc = try SlotScreenFixture.document()

        let fromInstance = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try move(["Filled/Title"], into: "Board", in: doc)
        }
        #expect(fromInstance?.code == .insideInstance)
        let intoInstance = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try move(["Loose"], into: "Filled/Screen", in: doc)
        }
        #expect(intoInstance?.code == .insideInstance)
        let intoContentInstance = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try move(["Loose"], into: "Filled/Row1/ItemA", in: doc)
        }
        #expect(intoContentInstance?.code == .insideInstance)
        let insideContentInstance = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try move(["Filled/Row2/BLbl"], into: "Board", in: doc)
        }
        #expect(insideContentInstance?.code == .insideInstance)
    }

    @Test("An instance moved into its own slot is refused as a cycle")
    func ownSlotIsACycle() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try move(["Filled"], into: "Filled/List", in: doc)
        }
        #expect(refusal?.code == .wouldCreateCycle)
        let nested = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try move(["HostInst/Nest/Screen"], into: "HostInst/Nest/List", in: doc)
        }
        #expect(nested?.code == .wouldCreateCycle)
    }

    @Test("A move into a slot that would make a component contain itself is refused by the loop check")
    func loopIntoASlot() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try move(["PanelInst"], into: "PScr/List", in: doc)
        }
        #expect(refusal?.code == .wouldCloseComponentLoop)
        #expect(doc.componentLoop(moving: "PanelInst", under: "PScr/List") != nil)
        #expect(doc.componentLoop(moving: "Loose", under: "PScr/List") == nil)
    }

    @Test("Moves outside slots plan exactly as the single-node planner plans them")
    func plainMovesUnchanged() throws {
        let doc = try SlotScreenFixture.document()
        let layout = SlotScreenFixture.layout(of: doc)

        let plan = try EditPlanner.planMove(
            nodeIDs: ["Loose"], into: "Stack", at: 0, keepingDrawnPlace: PenPoint(x: 0, y: 0), in: doc, layout: layout
        )
        let single = try EditPlanner.planMove(
            nodeID: "Loose", into: "Stack", at: 0, keepingDrawnPlace: PenPoint(x: 0, y: 0), in: doc, layout: layout
        )
        #expect(plan.operations == single)
        #expect(plan.placedIDs == ["Loose"])
    }

    @Test("The single-node planner still refuses slot content and slots, so a node-by-node caller can't write stale fills")
    func singleNodePlannerRefusesSlots() throws {
        let doc = try SlotScreenFixture.document()
        let layout = SlotScreenFixture.layout(of: doc)

        let fromSlot = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planMove(nodeID: "Filled/Row3/ItemA", into: "Filled/List", at: 0, in: doc, layout: layout)
        }
        #expect(fromSlot?.code == .insideInstance)
        let intoSlot = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planMove(nodeID: "Loose", into: "Filled/List", in: doc, layout: layout)
        }
        #expect(intoSlot != nil)
    }
}
