//
//  SlotInsertDeleteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Insert (creation and paste), delete and duplicate on slot content, each written as one
/// `children` override of the slot (Penumbra spec §13.5 rules 4–6 and 8).
@MainActor
struct SlotInsertDeleteTests {
    private func rectangle(_ id: String) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10))))
    }

    private func childrenWrites(_ operations: [EditOperation]) -> [String] {
        operations.compactMap { operation in
            guard case let .overrideDescendant(op) = operation, op.properties["children"] != nil else { return nil }
            return "\(op.refNodeID)|\(op.descendantID)"
        }
    }

    // MARK: - Insert

    @Test("A node inserted into a slot joins its fill at the index")
    func insertIntoAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planInsert([rectangle("NewR")], into: "Filled/List", at: 1, in: doc)

        #expect(childrenWrites(plan.operations) == ["Filled|List"])
        #expect(plan.operations.count == 1)
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "NewR", "Row2", "Row3"])
        #expect(plan.placedIDs == ["Filled/NewR"])
    }

    @Test("A node whose id is taken anywhere, in a fill included, takes a fresh one")
    func insertedIDsStayUnique() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planInsert([rectangle("NRow1"), rectangle("Loose")], into: "Filled/List", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let ids = try #require(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc))
        #expect(ids.count == 5)
        #expect(!ids.contains("NRow1"))
        #expect(!ids.contains("Loose"))
        #expect(plan.placedIDs == ids.suffix(2).map { "Filled/\($0)" })
    }

    @Test("An insert into default content copies it into a fill first")
    func insertIntoDefault() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planInsert([rectangle("NewR")], into: "Default/List", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(plan.materializedSlotIDs == ["Default/List"])
        #expect(doc.slot("Default/List")?.contentIDs == [plan.renamed("Default/Empty1/EmptyState"), "Default/NewR"])
    }

    @Test("An insert outside slots is an ordinary insert")
    func insertIntoTheDocument() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planInsert([rectangle("NewR")], into: "Board", at: 0, in: doc)

        #expect(plan.operations == [.insertNode(EditOperation.InsertNode(node: rectangle("NewR"), parentID: "Board", index: 0))])
        #expect(plan.placedIDs == ["NewR"])
    }

    @Test("An insert of a component's instance that would close a loop is refused")
    func insertLoop() throws {
        let doc = try SlotScreenFixture.document()
        let panel = PenNode(id: "P2", common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: "Panel")))

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planInsert([panel], into: "PScr/List", in: doc)
        }
        #expect(refusal?.code == .wouldCloseComponentLoop)
    }

    @Test("An insert inside an instance outside its slots is refused")
    func insertInsideInstance() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planInsert([rectangle("NewR")], into: "Filled/Screen", in: doc)
        }
        #expect(refusal?.code == .insideInstance)
    }

    // MARK: - Delete

    @Test("Deleting slot content rewrites the fill without it")
    func deleteFromAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDelete(nodeIDs: ["Filled/Row2/ItemB"], in: doc)

        #expect(childrenWrites(plan.operations) == ["Filled|List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row3"])
        #expect(plan.nodeIDs == ["Filled/Row2/ItemB"])
    }

    @Test("Deleting all of a slot's content leaves it Empty, not Default")
    func deleteEverything() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDelete(
            nodeIDs: ["Filled/Row1/ItemA", "Filled/Row2/ItemB", "Filled/Row3/ItemA", "Loose"], in: doc
        )
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.slot("Filled/List")?.state == .empty)
        #expect(doc.node(id: "Loose") == nil)
        #expect(childrenWrites(plan.operations) == ["Filled|List"])
    }

    @Test("Deleting default content copies it into a fill first, then deletes")
    func deleteDefault() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDelete(nodeIDs: ["Default/Empty1/EmptyState"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.slot("Default/List")?.state == .empty)
        #expect(SlotScreenFixture.entry("Empty1/ETxt", of: "Default", in: doc) == nil)
    }

    @Test("An instance's own node is still refused")
    func deleteInsideInstance() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planDelete(nodeIDs: ["Filled/Title"], in: doc)
        }
        #expect(refusal?.code == .insideInstance)
    }

    // MARK: - Duplicate

    @Test("Duplicating slot content puts the copy after it, fresh ids, values kept")
    func duplicateInAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["Filled/Row2/ItemB"], in: doc)

        #expect(childrenWrites(plan.operations) == ["Filled|List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        let ids = try #require(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc))
        try #require(ids.count == 4)
        #expect(ids[0 ... 1] == ["Row1", "Row2"])
        #expect(ids[3] == "Row3")
        #expect(plan.placedIDs == ["Filled/\(ids[2])/ItemB"])
        let rows = try TreeView.rows(of: doc, root: "Filled", expandInstances: true, properties: ["kind.content"])
        #expect(rows.first { $0.id == "Filled/\(ids[2])/BLbl" }?.properties?["kind.content"] == .string("Second"))
    }

    @Test("Duplicating default content copies the default into a fill first")
    func duplicateDefault() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["Default/Empty1/EmptyState"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.slot("Default/List")?.layerCount == 2)
        #expect(Set(doc.slot("Default/List")?.contentIDs ?? []).count == 2)
    }
}
