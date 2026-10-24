//
//  PlacedIDsAndOrderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Where several nodes moved forward within one slot land, and the ids
/// ``StructuralEditPlan/placedIDs`` names: the ids an editor selects — a stored node,
/// an instance among them, by its own id; slot content by its expanded id.
@MainActor
struct PlacedIDsAndOrderTests {
    private func rectangle(_ id: String) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10))))
    }

    // MARK: - Order

    @Test("Several nodes moved forward in one slot land together, the index counted with them taken out")
    func forwardRun() throws {
        let doc = try SlotScreenFixture.document()
        let insert = try EditPlanner.planInsert([rectangle("NewR")], into: "Filled/List", in: doc)
        try SlotScreenFixture.apply(insert.operations, to: doc)
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row2", "Row3", "NewR"])

        // Between Row3 and NewR: index 1 of [Row3, NewR], the list without the moving nodes.
        let plan = try EditPlanner.planMove(
            nodeIDs: ["Filled/Row1/ItemA", "Filled/Row2/ItemB"], into: "Filled/List", at: 1,
            in: doc, layout: SlotScreenFixture.layout(of: doc)
        )
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row3", "Row1", "Row2", "NewR"])
    }

    @Test("Several nodes moved backward in one slot still land together")
    func backwardRun() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planMove(
            nodeIDs: ["Filled/Row2/ItemB", "Filled/Row3/ItemA"], into: "Filled/List", at: 0,
            in: doc, layout: SlotScreenFixture.layout(of: doc)
        )
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row2", "Row3", "Row1"])
    }

    // MARK: - Placed ids

    @Test("An instance moved out of a slot is named by its own id, as the selection names it")
    func movedOutInstance() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planMove(
            nodeIDs: ["Filled/Row2/ItemB"], into: "Board", in: doc, layout: SlotScreenFixture.layout(of: doc)
        )

        #expect(plan.placedIDs == ["Row2"])
    }

    @Test("A stored instance moved outside slots is named by its own id")
    func storedMove() throws {
        let doc = try ConnectorFixture.document()
        let layout = PenLayoutState(document: PenVariableResolver.resolve(doc.expandedDocument().0))

        let plan = try EditPlanner.planMove(nodeIDs: ["Chip"], into: nil, in: doc, layout: layout)

        #expect(plan.placedIDs == ["Chip"])
    }

    @Test("A duplicated or inserted stored instance is named by its own id")
    func duplicateAndInsert() throws {
        let doc = try ConnectorFixture.document()
        let instance = PenNode(id: "NewI", common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: "Comp")))

        let duplicate = try EditPlanner.planDuplicate(nodeIDs: ["Chip"], in: doc)
        let insert = try EditPlanner.planInsert([instance], into: "Board", in: doc)

        #expect(duplicate.placedIDs.allSatisfy { !$0.contains("/") })
        #expect(insert.placedIDs == ["NewI"])
    }

    @Test("Slot content keeps its expanded id")
    func slotContent() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["Filled/Row1/ItemA"], in: doc)

        #expect(plan.placedIDs.first?.hasPrefix("Filled/") == true)
        #expect(plan.placedIDs.first?.hasSuffix("/ItemA") == true)
    }

    // MARK: - Duplicate validation

    @Test("Duplicating a parent's last two children plans, each copy after its original")
    func duplicateLastTwo() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["CardC", "Chip"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let children = doc.childIDs(of: "Board")
        #expect(children.count == 6)
        #expect(children[2] == "CardC" && children[4] == "Chip")
        #expect([children[3], children[5]] == plan.placedIDs)
    }
}
