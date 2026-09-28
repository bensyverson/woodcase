//
//  ComponentIntrospectionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct ComponentIntrospectionTests {
    // MARK: - Basic Introspection

    @Test("Inspect component returns correct name and ID")
    func inspectBasic() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "label", common: PenNodeCommon(name: "Label"), kind: .text(PenNode.TextData())),
            ]))
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc)

        let surface = editable.inspectComponent("comp1")

        #expect(surface != nil)
        #expect(surface?.componentID == "comp1")
        #expect(surface?.componentName == "Button")
    }

    @Test("Inspect non-existent component returns nil")
    func inspectMissing() {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)

        #expect(editable.inspectComponent("missing") == nil)
    }

    // MARK: - Slots

    @Test("Component with slot frames returns slot info")
    func inspectSlots() {
        let slotFrame = PenNode(
            id: "content-slot",
            common: PenNodeCommon(name: "Content"),
            kind: .frame(PenNode.FrameData(slot: ["frame", "text"]))
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Card", reusable: true),
            kind: .frame(PenNode.FrameData(children: [slotFrame]))
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc)

        let surface = editable.inspectComponent("comp1")

        #expect(surface?.slots.count == 1)
        #expect(surface?.slots.first?.frameID == "content-slot")
        #expect(surface?.slots.first?.frameName == "Content")
        #expect(surface?.slots.first?.acceptedTypes == ["frame", "text"])
    }

    @Test("Component without slots returns empty slots array")
    func inspectNoSlots() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "label", common: PenNodeCommon(), kind: .text(PenNode.TextData())),
            ]))
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc)

        let surface = editable.inspectComponent("comp1")

        #expect(surface?.slots.isEmpty == true)
    }

    // MARK: - Overridable Nodes

    @Test("Various node types report correct overridable properties")
    func inspectOverridableNodes() {
        let rect = PenNode(
            id: "bg",
            common: PenNodeCommon(name: "Background"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Card", reusable: true),
            kind: .frame(PenNode.FrameData(children: [rect, label]))
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc)

        let surface = editable.inspectComponent("comp1")

        // Should include the root frame + 2 children = 3 overridable nodes
        #expect(surface?.overridableNodes.count == 3)

        // Check that the rectangle node has rectangle properties
        let bgNode = surface?.overridableNodes.first { $0.nodeID == "bg" }
        #expect(bgNode?.nodeType == "rectangle")
        #expect(bgNode?.properties.contains("kind.fills") == true)
        #expect(bgNode?.properties.contains("kind.cornerRadius") == true)

        // Check that the text node has text properties
        let labelNode = surface?.overridableNodes.first { $0.nodeID == "label" }
        #expect(labelNode?.nodeType == "text")
        #expect(labelNode?.properties.contains("kind.content") == true)
        #expect(labelNode?.properties.contains("kind.fontFamily") == true)
    }

    // MARK: - Codable

    @Test("ComponentSurface round-trips through Codable")
    func surfaceCodable() throws {
        let surface = ComponentSurface(
            componentID: "comp1",
            componentName: "Button",
            slots: [ComponentSlotInfo(frameID: "slot1", frameName: "Content", acceptedTypes: ["frame"])],
            overridableNodes: [OverridableNode(
                nodeID: "label",
                nodeName: "Label",
                nodeType: "text",
                properties: Set(["kind.content", "kind.fontSize"])
            )]
        )

        let data = try JSONEncoder().encode(surface)
        let decoded = try JSONDecoder().decode(ComponentSurface.self, from: data)

        #expect(surface == decoded)
    }
}
