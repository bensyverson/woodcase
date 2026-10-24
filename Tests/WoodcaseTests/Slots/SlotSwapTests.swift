//
//  SlotSwapTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Swapping an instance's component keeps each fill on the new component's slot of the
/// same name, and drops and reports the others (``EditPlanner/planSwap(instanceID:to:in:)``;
/// Penumbra spec §13.5 rule 14).
@MainActor
struct SlotSwapTests {
    /// The fixture plus `Screen2`, a variant whose `List` slot has another id (`List2`)
    /// and which adds a `Footer` slot, and `Bare`, a variant with no slot at all.
    private func document() throws -> EditableDocument {
        let doc = try SlotScreenFixture.document()
        let variants = """
        {"version": "2.19", "children": [
          {"id": "Screen2", "type": "frame", "name": "Screen Dark", "reusable": true, "x": 2000, "y": 0,
           "width": 240, "height": "fit_content", "layout": "vertical", "children": [
            {"id": "List2", "type": "frame", "name": "List", "slot": ["ItemA"], "width": "fill_container",
             "height": "fit_content", "layout": "vertical"},
            {"id": "Footer", "type": "frame", "name": "Footer", "slot": [], "width": 100, "height": 20}]},
          {"id": "Bare", "type": "frame", "name": "Bare", "reusable": true, "x": 2400, "y": 0,
           "width": 240, "height": 100, "layout": "vertical", "children": [
            {"id": "BareT", "type": "text", "name": "Title", "content": "Bare"}]}
        ]}
        """
        let extra = try PenParser.parse(Data(variants.utf8))
        for node in extra.children {
            try doc.apply(.insertNode(EditOperation.InsertNode(node: node, parentID: nil)))
        }
        return doc
    }

    @Test("A fill moves to the new component's slot of the same name")
    func fillFollowsTheName() throws {
        let doc = try document()

        let plan = try EditPlanner.planSwap(instanceID: "Filled", to: "Screen2", in: doc)

        #expect(plan.keptSlots == ["List"])
        #expect(plan.droppedSlots.isEmpty)
        try SlotScreenFixture.apply(plan.operations, to: doc)
        guard case let .ref(data)? = doc.node(id: "Filled")?.kind else { Issue.record("not a ref"); return }
        #expect(data.ref == "Screen2")
        #expect(SlotScreenFixture.fillIDs("List2", of: "Filled", in: doc) == ["Row1", "Row2", "Row3"])
        #expect(SlotScreenFixture.entry("List", of: "Filled", in: doc) == nil)
        #expect(doc.slot("Filled/List2")?.contentIDs == ["Filled/Row1/ItemA", "Filled/Row2/ItemB", "Filled/Row3/ItemA"])
    }

    @Test("A fill whose slot the new component lacks is dropped and reported")
    func unmatchedFillIsDropped() throws {
        let doc = try document()

        let plan = try EditPlanner.planSwap(instanceID: "Filled/Screen", to: "Bare", in: doc)

        #expect(plan.keptSlots.isEmpty)
        #expect(plan.droppedSlots == ["List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(SlotScreenFixture.entry("List", of: "Filled", in: doc) == nil)
    }

    @Test("An instance with no fills swaps with nothing kept or dropped, its other overrides as they were")
    func noFills() throws {
        let doc = try document()

        let plan = try EditPlanner.planSwap(instanceID: "Default", to: "Screen2", in: doc)

        #expect(plan.keptSlots.isEmpty)
        #expect(plan.droppedSlots.isEmpty)
        try SlotScreenFixture.apply(plan.operations, to: doc)
        guard case let .ref(data)? = doc.node(id: "Default")?.kind else { Issue.record("not a ref"); return }
        #expect(data.ref == "Screen2")
        #expect(SlotScreenFixture.entry("Empty1/ETxt", of: "Default", in: doc)?["content"] == .string("Nothing yet"))
    }

    @Test("An instance in a fill swaps inside that fill, its own fills kept by name")
    func swapInsideAFill() throws {
        let doc = try document()

        let plan = try EditPlanner.planSwap(instanceID: "HostInst/Nest/Screen", to: "Screen2", in: doc)

        #expect(plan.keptSlots == ["List"])
        try SlotScreenFixture.apply(plan.operations, to: doc)
        #expect(doc.slot("HostInst/Nest/List2")?.contentIDs == ["HostInst/Nest/NRow1/ItemA"])
        #expect(doc.slot("HostInst/Body")?.contentIDs == ["HostInst/Nest/Screen2"])
    }

    @Test("A swap that would close a component loop is refused")
    func swapLoop() throws {
        let doc = try document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planSwap(instanceID: "PScr", to: "Panel", in: doc)
        }
        #expect(refusal?.code == .wouldCloseComponentLoop)
    }

    @Test("A swap of something that is not an instance, or to no such component, is refused")
    func swapRefusals() throws {
        let doc = try document()

        let notInstance = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planSwap(instanceID: "Loose", to: "Screen2", in: doc)
        }
        #expect(notInstance?.code == .overrideOutsideInstance)
        let missing = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planSwap(instanceID: "Filled", to: "Gone", in: doc)
        }
        #expect(missing?.code == .addressNotFound)
    }
}
