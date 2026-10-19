//
//  IntentRoutingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditPlanner/plan(_:routedAt:in:)``: an editor's intent planned wherever each property
/// is stored — a set split between an instance's `ref` node (`common.`) and its overrides,
/// a bind of a property an instance overrides written as an override of `$name`, and an
/// unbind there as an override of the value the variable resolves to.
@MainActor
struct IntentRoutingTests {
    /// `Board` holds `Plain`, a rectangle with storage of its own; `Chip`, an instance of
    /// `Button`; and `Filled`, an instance of `Card` that wrote `Note` into its slot.
    /// `Button`'s fill is bound to `brand` and its `Label`'s to `ink`.
    static let json = """
    {
      "version": "2.19",
      "variables": {
        "brand": { "type": "color", "value": "#E5484D" },
        "ink": { "type": "color", "value": "#111111" },
        "half": { "type": "number", "value": 0.5 }
      },
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 800, "height": 600, "layout": "none",
          "children": [
          { "type": "rectangle", "id": "Plain", "x": 10, "y": 10, "width": 50, "height": 30, "fill": "$ink" },
          { "type": "ref", "id": "Chip", "ref": "Button", "x": 50, "y": 300 },
          { "type": "ref", "id": "Filled", "ref": "Card", "x": 300, "y": 300, "descendants": {
            "Body": { "children": [
              { "type": "text", "id": "Note", "content": "Hello", "fill": "#333333" }
            ] }
          } }
        ] },
        { "type": "frame", "id": "Button", "reusable": true, "x": 0, "y": 1000, "width": 120, "height": 40,
          "layout": "none", "fill": "$brand", "children": [
          { "type": "text", "id": "Label", "x": 4, "y": 4, "content": "Go", "fill": "$ink" }
        ] },
        { "type": "frame", "id": "Card", "reusable": true, "x": 300, "y": 1000, "width": 200,
          "height": "fit_content", "layout": "vertical", "children": [
          { "type": "frame", "id": "Body", "slot": ["text"], "layout": "vertical",
            "width": "fit_content", "height": "fit_content" }
        ] }
      ]
    }
    """

    /// A fresh copy of the fixture.
    static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    private static let chip = ResolvedNodeAddress.node(id: "Chip")
    private static let label = ResolvedNodeAddress.instanceDescendant(refID: "Chip", descendantKey: "Label")
    private static let note = ResolvedNodeAddress.instanceDescendant(refID: "Filled", descendantKey: "Note")

    private func refusal(_ intent: EditIntent, at target: ResolvedNodeAddress, in document: EditableDocument) -> EditRefusal? {
        do {
            _ = try EditPlanner.plan(intent, routedAt: target, in: document)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - set

    @Test("A set on a node with storage of its own plans as a plain set")
    func ownSet() throws {
        let document = try Self.document()
        let intent = EditIntent.set(["kind.fills": "#00FF00", "common.opacity": 0.5])
        let routed = try EditPlanner.plan(intent, routedAt: .node(id: "Plain"), in: document)
        #expect(try routed == EditPlanner.plan(intent, at: .node(id: "Plain"), in: document))
    }

    @Test("A set on an instance root writes common properties on the ref node and the rest as root overrides")
    func instanceRootSet() throws {
        let document = try Self.document()
        let plan = try EditPlanner.plan(
            .set(["common.x": 80, "kind.fills": "#00FF00"]), routedAt: Self.chip, in: document
        )
        #expect(plan.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Chip", properties: ["common.x": 80])),
            .overrideRoot(EditOperation.OverrideRoot(refNodeID: "Chip", properties: ["fill": "#00FF00"])),
        ])
        #expect(plan.targetID == "Chip")
        #expect(plan.storage == .instanceOverride)
    }

    @Test("A set of an instance root's common properties alone is stored on the ref node")
    func instanceRootOwnSet() throws {
        let document = try Self.document()
        let plan = try EditPlanner.plan(.set(["common.opacity": 0.5]), routedAt: Self.chip, in: document)
        #expect(plan.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Chip", properties: ["common.opacity": 0.5])),
        ])
        #expect(plan.storage == .node)
    }

    @Test("A set inside an instance, common properties included, is an override on the instance")
    func descendantSet() throws {
        let document = try Self.document()
        let plan = try EditPlanner.plan(
            .set(["common.opacity": 0.5, "kind.content": "Buy"]), routedAt: Self.label, in: document
        )
        #expect(plan.operations == [
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "Chip", descendantID: "Label", properties: ["content": "Buy", "opacity": 0.5]
            )),
        ])
        #expect(plan.storage == .instanceOverride)
    }

    @Test("A set on content an instance wrote into its slot is written into that slot's fill, not refused")
    func slotContentSet() throws {
        let document = try Self.document()
        // A plain set is refused there, since the content sits inside an instance.
        #expect(throws: EditRefusal.self) {
            try EditPlanner.plan(.set(["kind.content": "Bye"]), at: Self.note, in: document)
        }
        let plan = try EditPlanner.plan(.set(["kind.content": "Bye"]), routedAt: Self.note, in: document)
        for operation in plan.operations {
            try document.apply(operation)
        }
        let shown = try #require(document.inspect(Self.note)?.sourceNode)
        #expect(try NodePropertyCodec.value(at: "kind.content", of: shown) == "Bye")
    }

    // MARK: - bind

    @Test("A bind inside an instance is an override of the variable reference")
    func descendantBind() throws {
        let document = try Self.document()
        let plan = try EditPlanner.plan(.bind(property: "kind.fills", variable: "brand"), routedAt: Self.label, in: document)
        #expect(plan.operations == [
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "Chip", descendantID: "Label", properties: ["fill": "$brand"]
            )),
        ])
    }

    @Test("A bind at an instance root is a root override for the component's properties, a set for its own")
    func instanceRootBind() throws {
        let document = try Self.document()
        let fill = try EditPlanner.plan(.bind(property: "kind.fills", variable: "$ink"), routedAt: Self.chip, in: document)
        #expect(fill.operations == [
            .overrideRoot(EditOperation.OverrideRoot(refNodeID: "Chip", properties: ["fill": "$ink"])),
        ])
        let opacity = try EditPlanner.plan(.bind(property: "common.opacity", variable: "half"), routedAt: Self.chip, in: document)
        #expect(opacity.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Chip", properties: ["common.opacity": "$half"])),
        ])
    }

    @Test("A bind overriding an instance to a variable the document lacks is refused, as a bind is")
    func undefinedBind() throws {
        let document = try Self.document()
        let refused = try #require(refusal(.bind(property: "kind.fills", variable: "nope"), at: Self.label, in: document))
        #expect(refused.code == .undefinedVariable)
        let mismatched = try #require(refusal(.bind(property: "kind.fills", variable: "half"), at: Self.label, in: document))
        #expect(mismatched.code == .variableTypeMismatch)
    }

    // MARK: - unbind

    @Test("An unbind inside an instance overrides the value the component's binding resolves to")
    func descendantUnbind() throws {
        let document = try Self.document()
        let plan = try EditPlanner.plan(.unbind(property: "kind.fills"), routedAt: Self.label, in: document)
        #expect(plan.operations == [
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "Chip", descendantID: "Label", properties: ["fill": "#111111"]
            )),
        ])
    }

    @Test("An unbind of an instance root's binding is a root override of its value, the instance's binding winning")
    func instanceRootUnbind() throws {
        let document = try Self.document()
        let plan = try EditPlanner.plan(.unbind(property: "kind.fills"), routedAt: Self.chip, in: document)
        #expect(plan.operations == [
            .overrideRoot(EditOperation.OverrideRoot(refNodeID: "Chip", properties: ["fill": "#E5484D"])),
        ])
        try document.apply(.overrideRoot(EditOperation.OverrideRoot(refNodeID: "Chip", properties: ["fill": "$ink"])))
        let overridden = try EditPlanner.plan(.unbind(property: "kind.fills"), routedAt: Self.chip, in: document)
        #expect(overridden.operations == [
            .overrideRoot(EditOperation.OverrideRoot(refNodeID: "Chip", properties: ["fill": "#111111"])),
        ])
    }

    @Test("An unbind inside an instance of a property bound to nothing is refused with notBound")
    func unboundUnbind() throws {
        let document = try Self.document()
        let refused = try #require(refusal(.unbind(property: "kind.content"), at: Self.label, in: document))
        #expect(refused.code == .notBound)
    }

    @Test("Bind and unbind on a node with storage of its own plan as they always have")
    func ownBindAndUnbind() throws {
        let document = try Self.document()
        for intent in [EditIntent.bind(property: "kind.fills", variable: "brand"), .unbind(property: "kind.fills")] {
            let routed = try EditPlanner.plan(intent, routedAt: .node(id: "Plain"), in: document)
            #expect(try routed == EditPlanner.plan(intent, at: .node(id: "Plain"), in: document))
        }
    }

    // MARK: - Overrides asked for by name

    @Test("An override or a reset asked for by name plans as it always has")
    func namedOverrides() throws {
        let document = try Self.document()
        for intent in [EditIntent.override(["kind.content": "Buy"]), .resetOverride(["kind.content"])] {
            let routed = try EditPlanner.plan(intent, routedAt: Self.label, in: document)
            #expect(try routed == EditPlanner.plan(intent, at: Self.label, in: document))
        }
    }
}
