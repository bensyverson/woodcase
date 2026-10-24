//
//  InstanceSlotReadTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An instance's slots as Layers, the inspector and the slot menus read them
/// (``EditableDocument/slots(ofInstance:)``, ``EditableDocument/slot(_:)``,
/// ``EditableDocument/slot(containing:)``): state, content, suggested components.
@MainActor
struct InstanceSlotReadTests {
    @Test("A slot showing its component's content reads Default, with that content")
    func defaultSlot() throws {
        let doc = try SlotScreenFixture.document()

        let slots = doc.slots(ofInstance: "Default")

        #expect(slots.map(\.id) == ["Default/List"])
        let list = try #require(slots.first)
        #expect(list.state == .default)
        #expect(list.name == "List")
        #expect(list.refID == "Default")
        #expect(list.componentID == "Screen")
        #expect(list.componentSlotID == "List")
        #expect(list.instanceID == "Default/Screen")
        #expect(list.contentIDs == ["Default/Empty1/EmptyState"])
        #expect(list.layerCount == 1)
    }

    @Test("A filled slot reads Filled, its content the fill's nodes in order")
    func filledSlot() throws {
        let doc = try SlotScreenFixture.document()

        let list = try #require(doc.slots(ofInstance: "Filled").first)

        #expect(list.state == .filled)
        #expect(list.contentIDs == ["Filled/Row1/ItemA", "Filled/Row2/ItemB", "Filled/Row3/ItemA"])
        #expect(list.layerCount == 3)
    }

    @Test("A slot filled with nothing reads Empty")
    func emptiedSlot() throws {
        let doc = try SlotScreenFixture.document()

        let list = try #require(doc.slots(ofInstance: "Emptied").first)

        #expect(list.state == .empty)
        #expect(list.contentIDs.isEmpty)
    }

    @Test("Suggested components carry their names, a missing one marked")
    func suggestedComponents() throws {
        let doc = try SlotScreenFixture.document()

        let list = try #require(doc.slots(ofInstance: "Filled").first)

        #expect(list.suggestedComponents.map(\.id) == ["ItemA", "ItemB", "Gone"])
        #expect(list.suggestedComponents.map(\.name) == ["Item/A", "Item/B", nil])
        #expect(list.suggestedComponents.map(\.isMissing) == [false, false, true])
    }

    @Test("The instance's expanded root id reads the same slots as its ref")
    func expandedRootReads() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.slots(ofInstance: "Filled/Screen").map(\.id) == ["Filled/List"])
    }

    @Test("A nested instance's slot is its own, stored on the outermost instance")
    func nestedInstanceSlot() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.slots(ofInstance: "PanelInst").isEmpty)
        let list = try #require(doc.slots(ofInstance: "PanelInst/PScr/Screen").first)
        #expect(list.id == "PanelInst/PScr/List")
        #expect(list.refID == "PanelInst")
        #expect(list.instanceID == "PanelInst/PScr/Screen")
        #expect(list.state == .default)
        #expect(list.contentIDs == ["PanelInst/PScr/Empty1/EmptyState"])
    }

    @Test("An instance placed in a fill shows its own slot, stored on the outermost instance")
    func slotInsideAFill() throws {
        let doc = try SlotScreenFixture.document()

        let body = try #require(doc.slots(ofInstance: "HostInst").first)
        #expect(body.id == "HostInst/Body")
        #expect(body.contentIDs == ["HostInst/Nest/Screen"])

        let list = try #require(doc.slots(ofInstance: "HostInst/Nest/Screen").first)
        #expect(list.id == "HostInst/Nest/List")
        #expect(list.refID == "HostInst")
        #expect(list.state == .filled)
        #expect(list.contentIDs == ["HostInst/Nest/NRow1/ItemA"])
    }

    @Test("A slot frame's id reads its slot; anything else reads none")
    func slotByID() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.slot("Filled/List")?.state == .filled)
        #expect(doc.slot("HostInst/Nest/List")?.refID == "HostInst")
        #expect(doc.slot("Filled/Title") == nil)
        #expect(doc.slot("List") == nil)
        #expect(doc.slot("Loose") == nil)
    }

    @Test("Content reads the slot that holds it, at any depth; the slot frame and the instance's own nodes read none")
    func slotContaining() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.slot(containing: "Filled/Row2/ItemB")?.id == "Filled/List")
        #expect(doc.slot(containing: "Default/Empty1/EmptyState")?.id == "Default/List")
        #expect(doc.slot(containing: "HostInst/Nest/NRow1/ItemA")?.id == "HostInst/Nest/List")
        #expect(doc.slot(containing: "HostInst/Nest/Screen")?.id == "HostInst/Body")
        #expect(doc.slot(containing: "Filled/Row2/BLbl") == nil)
        #expect(doc.slot(containing: "Filled/List") == nil)
        #expect(doc.slot(containing: "Filled/Title") == nil)
        #expect(doc.slot(containing: "Loose") == nil)
    }

    @Test("A node that is not an instance has no slots")
    func notAnInstance() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.slots(ofInstance: "Loose").isEmpty)
        #expect(doc.slots(ofInstance: "Screen").isEmpty)
        #expect(doc.slots(ofInstance: "Nowhere").isEmpty)
    }
}
