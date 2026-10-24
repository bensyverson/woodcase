//
//  SlotAuthoringTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Making and removing a slot in a component, and editing its suggested components
/// (``EditPlanner/planMakeSlot(frameID:in:)``, ``EditPlanner/planRemoveSlot(frameID:in:)``,
/// ``EditPlanner/planSuggestedComponents(_:frameID:in:)``; Penumbra spec §13.5 rules 9–10).
@MainActor
struct SlotAuthoringTests {
    private func slotList(_ id: String, in doc: EditableDocument) -> [String]? {
        guard case let .frame(data)? = doc.node(id: id)?.kind else { return nil }
        return data.slot
    }

    @Test("Make Slot writes an empty suggestion list on a frame inside a component")
    func makeSlot() throws {
        let doc = try SlotScreenFixture.document()

        let operations = try EditPlanner.planMakeSlot(frameID: "Title2", in: Self.withFrame(doc))
        try SlotScreenFixture.apply(operations, to: doc)

        #expect(slotList("Title2", in: doc) == [])
    }

    @Test("Make Slot is refused on a component's own frame, outside a component, and on a non-frame")
    func makeSlotRefusals() throws {
        let doc = try SlotScreenFixture.document()

        for id in ["Screen", "Board", "Title"] {
            let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
                try EditPlanner.planMakeSlot(frameID: id, in: doc)
            }
            #expect(refusal?.code == .slotNotAllowed, "\(id)")
        }
    }

    @Test("Suggested components are written in the order given")
    func suggestions() throws {
        let doc = try SlotScreenFixture.document()

        let operations = try EditPlanner.planSuggestedComponents(["ItemB", "ItemA"], frameID: "List", in: doc)
        try SlotScreenFixture.apply(operations, to: doc)

        #expect(slotList("List", in: doc) == ["ItemB", "ItemA"])
        #expect(doc.slot("Filled/List")?.suggestedComponents.map(\.id) == ["ItemB", "ItemA"])
    }

    @Test("Suggestions on a frame that is not a slot are refused")
    func suggestionsNeedASlot() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planSuggestedComponents(["ItemA"], frameID: "Board", in: doc)
        }
        #expect(refusal?.code == .notASlot)
    }

    @Test("Remove Slot names the instances that fill it and clears their fills in the same edit")
    func removeSlot() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planRemoveSlot(frameID: "List", in: doc)

        #expect(plan.filledInstanceIDs == ["Emptied/Screen", "Filled/Screen", "HostInst/Nest/Screen"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(slotList("List", in: doc) == nil)
        #expect(SlotScreenFixture.entry("List", of: "Filled", in: doc) == nil)
        #expect(SlotScreenFixture.entry("List", of: "Emptied", in: doc) == nil)
        #expect(doc.slots(ofInstance: "Filled").isEmpty)
        #expect(SlotScreenFixture.expandedChildren(of: "HostInst/Nest/List", in: doc) == ["HostInst/Nest/Empty1/EmptyState"])
    }

    /// The fixture with `Title2`, an empty frame, added to `Screen`.
    private static func withFrame(_ doc: EditableDocument) throws -> EditableDocument {
        let frame = PenNode(id: "Title2", common: PenNodeCommon(), kind: .frame(PenNode.FrameData()))
        try doc.apply(.insertNode(EditOperation.InsertNode(node: frame, parentID: "Screen")))
        return doc
    }
}
