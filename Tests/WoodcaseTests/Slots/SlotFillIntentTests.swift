//
//  SlotFillIntentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Replace Content With, Empty Slot and Reset Slot
/// (``EditPlanner/planReplaceSlotContent(slotID:with:count:in:)``,
/// ``EditPlanner/planEmptySlot(slotID:in:)``, ``EditPlanner/planResetSlot(slotID:in:)``;
/// Penumbra spec §13.5 rules 5, 6 and 11).
@MainActor
struct SlotFillIntentTests {
    /// The `ref` each top-level node of a fill names.
    private func refs(_ key: String, of refID: String, in doc: EditableDocument) -> [String] {
        guard case let .array(children)? = SlotScreenFixture.entry(key, of: refID, in: doc)?["children"] else { return [] }
        return children.compactMap { value in
            guard case let .dictionary(node) = value, case let .string(ref)? = node["ref"] else { return nil }
            return ref
        }
    }

    // MARK: - Replace

    @Test("Replace fills the slot with as many instances as it had layers")
    func replaceKeepsTheCount() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planReplaceSlotContent(slotID: "Filled/List", with: "ItemB", in: doc)

        #expect(plan.operations.count == 1)
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(refs("List", of: "Filled", in: doc) == ["ItemB", "ItemB", "ItemB"])
        let ids = try #require(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc))
        #expect(Set(ids).isDisjoint(with: ["Row1", "Row2", "Row3"]))
        #expect(plan.placedIDs == ids.map { "Filled/\($0)/ItemB" })
        #expect(doc.slot("Filled/List")?.contentIDs == plan.placedIDs)
    }

    @Test("Replace on an empty slot places one instance")
    func replaceEmptyPlacesOne() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planReplaceSlotContent(slotID: "Emptied/List", with: "ItemA", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(refs("List", of: "Emptied", in: doc) == ["ItemA"])
    }

    @Test("Replace takes an explicit count")
    func replaceWithCount() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planReplaceSlotContent(slotID: "Filled/List", with: "ItemA", count: 2, in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(refs("List", of: "Filled", in: doc) == ["ItemA", "ItemA"])
    }

    @Test("Replace on default content copies it first, so the default's keys go")
    func replaceDefault() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planReplaceSlotContent(slotID: "Default/List", with: "ItemA", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(refs("List", of: "Default", in: doc) == ["ItemA"])
        #expect(SlotScreenFixture.entry("Empty1/ETxt", of: "Default", in: doc) == nil)
        #expect(doc.slot("Default/List")?.state == .filled)
    }

    @Test("In a free slot each new instance takes the place of the layer it replaces")
    func replaceKeepsPlaces() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planReplaceSlotContent(slotID: "FreeInst/Area", with: "ItemA", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        guard case let .array(children)? = SlotScreenFixture.entry("Area", of: "FreeInst", in: doc)?["children"],
              case let .dictionary(item)? = children.first
        else { Issue.record("no fill"); return }
        #expect(item["ref"] == .string("ItemA"))
        #expect(item["x"] == .int(5))
        #expect(item["y"] == .int(6))
    }

    @Test("Replace with a component that would contain itself is refused by the loop check")
    func replaceLoop() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planReplaceSlotContent(slotID: "PScr/List", with: "Panel", in: doc)
        }
        #expect(refusal?.code == .wouldCloseComponentLoop)
    }

    @Test("Replace with no such component, or on something that is not a slot, is refused")
    func replaceRefusals() throws {
        let doc = try SlotScreenFixture.document()

        let missing = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planReplaceSlotContent(slotID: "Filled/List", with: "Gone", in: doc)
        }
        #expect(missing?.code == .addressNotFound)
        let notSlot = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planReplaceSlotContent(slotID: "Filled/Title", with: "ItemA", in: doc)
        }
        #expect(notSlot?.code == .notASlot)
    }

    // MARK: - Empty and Reset

    @Test("Empty Slot leaves the slot with nothing, which is not its default")
    func emptySlot() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planEmptySlot(slotID: "Default/List", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.slot("Default/List")?.state == .empty)
        #expect(SlotScreenFixture.fillIDs("List", of: "Default", in: doc) == [])
        #expect(SlotScreenFixture.entry("Empty1/ETxt", of: "Default", in: doc) == nil)
    }

    @Test("Reset Slot removes the fill, so the default shows and follows the component")
    func resetSlot() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planResetSlot(slotID: "Filled/List", in: doc)

        #expect(plan.operations == [.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Filled", descendantID: "List", properties: [:], unset: ["children"]
        ))])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(doc.slot("Filled/List")?.state == .default)
        #expect(doc.slot("Filled/List")?.contentIDs == ["Filled/Empty1/EmptyState"])
    }

    @Test("Reset on a slot already at its default plans nothing")
    func resetDefault() throws {
        let doc = try SlotScreenFixture.document()

        #expect(try EditPlanner.planResetSlot(slotID: "Default/List", in: doc).operations.isEmpty)
    }

    @Test("Reset of a slot inside a fill rewrites that fill")
    func resetInsideAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planResetSlot(slotID: "HostInst/Nest/List", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.slot("HostInst/Nest/List")?.state == .default)
        #expect(doc.slot("HostInst/Body")?.contentIDs == ["HostInst/Nest/Screen"])
    }
}
