//
//  EditPlannerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the planner turns an intent and an address into stored edits.
@MainActor
struct EditPlannerTests {
    private func plan(_ intent: EditIntent, at raw: String, in document: EditableDocument) throws -> EditPlan {
        try EditPlanner.plan(intent, at: PlannerFixture.address(raw), in: document)
    }

    // MARK: - set

    @Test("A set on a node with storage of its own plans as setProperties on it")
    func setOnNode() throws {
        let document = try PlannerFixture.document()
        let plan = try plan(.set(["common.opacity": 0.5]), at: "Board/Free", in: document)

        #expect(plan.storage == .node)
        #expect(plan.targetID == "Fre01")
        #expect(plan.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Fre01", properties: ["common.opacity": 0.5])),
        ])
        #expect(plan.divergences.isEmpty)
    }

    @Test("A set on an instance descendant is refused, suggesting the override to write")
    func setOnDescendantIsRefused() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(.set(["kind.fills": "#FF0000"]), at: "Board/Chip/Label", in: document))

        #expect(refusal.code == .setInsideInstance)
        #expect(refusal.errorCode == "setInsideInstance")
        #expect(refusal.suggestion == "fill=#FF0000")
        #expect(refusal.message.contains("Board/Chip"))
        #expect(refusal.message.contains(##"{"op":"override","target":"Board/Chip/Label","props":{"fill":"#FF0000"}}"##),
                "\(refusal.message)")
    }

    @Test("A set on an instance descendant is refused the same way by resolved address")
    func setByResolvedAddress() throws {
        let document = try PlannerFixture.document()
        let byAddress = PlannerFixture.refusal(.set(["kind.content": "Go"]), at: "Board/Chip/Label", in: document)
        var byResolved: EditRefusal?
        do {
            _ = try EditPlanner.plan(
                .set(["kind.content": "Go"]),
                at: ResolvedNodeAddress.instanceDescendant(refID: "Chi01", descendantKey: "Lbl01"),
                in: document
            )
        } catch {
            byResolved = error
        }

        #expect(byAddress?.code == .setInsideInstance)
        #expect(byResolved?.code == .setInsideInstance)
        #expect(byResolved?.suggestion == byAddress?.suggestion)
    }

    @Test("A set on an instance root writes the ref node's own properties")
    func setOnInstanceRoot() throws {
        let document = try PlannerFixture.document()
        let plan = try plan(.set(["common.x": 120]), at: "Board/Chip", in: document)

        #expect(plan.storage == .node)
        #expect(plan.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Chi01", properties: ["common.x": 120])),
        ])
    }

    // MARK: - override and reset

    @Test("An override on an instance root plans as a root override")
    func overrideOnRoot() throws {
        let document = try PlannerFixture.document()
        let plan = try plan(.override(["width": 120]), at: "Board/Chip", in: document)

        #expect(plan.storage == .instanceOverride)
        #expect(plan.operations == [
            .overrideRoot(EditOperation.OverrideRoot(refNodeID: "Chi01", properties: ["width": 120], unset: [])),
        ])
    }

    @Test("A reset removes the override keys and writes none")
    func resetOverride() throws {
        let document = try PlannerFixture.document()
        let plan = try plan(.resetOverride(["kind.content"]), at: "Board/Chip/Label", in: document)

        #expect(plan.operations == [
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "Chi01", descendantID: "Lbl01", properties: [:], unset: ["content"]
            )),
        ])
    }

    @Test("An override on a plain node is refused with overrideOutsideInstance")
    func overrideOutsideInstance() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(.override(["opacity": 0.5]), at: "Board/Free", in: document))

        #expect(refusal.code == .overrideOutsideInstance)
        #expect(refusal.errorCode == "overrideOutsideInstance")
        #expect(refusal.message.contains("Board/Free"))
    }

    @Test("An override with nothing to write or unset is refused with noProperties")
    func overrideWithNothing() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(.override([:]), at: "Board/Chip/Label", in: document))

        #expect(refusal.code == .noProperties)
    }

    @Test("An address naming nothing is refused with addressNotFound")
    func missingAddress() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(.set(["common.opacity": 1]), at: "Board/Nope", in: document))

        #expect(refusal.code == .addressNotFound)
        #expect(refusal.address == "Board/Nope")
    }

    @Test("A property the node's type lacks is refused with unknownProperty")
    func unknownProperty() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(.set(["kind.content": "x"]), at: "Board/Free", in: document))

        #expect(refusal.code == .unknownProperty)
        #expect(refusal.property == "kind.content")
    }

    @Test("A value of the wrong form is refused with invalidForm and the expected form")
    func invalidForm() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(
            .set(["kind.fills": [["type": "solid"]]]), at: "Board/Free", in: document
        ))

        #expect(refusal.code == .invalidForm)
        #expect(refusal.property == "kind.fills")
        #expect(refusal.expected?.contains("color") == true)
    }

    // MARK: - bind and unbind

    @Test("A bind stores the variable reference")
    func bind() throws {
        let document = try PlannerFixture.document()
        let plan = try plan(.bind(property: "kind.fills", variable: "brand"), at: "Board/Free", in: document)

        #expect(plan.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Fre01", properties: ["kind.fills": "$brand"])),
        ])
    }

    @Test("A bind inside an instance is refused, suggesting the override that binds it")
    func bindInsideInstance() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(
            .bind(property: "kind.fills", variable: "$brand"), at: "Board/Chip/Label", in: document
        ))

        #expect(refusal.code == .setInsideInstance)
        #expect(refusal.suggestion == "fill=$brand")
    }

    @Test("An unbind inside an instance is refused, suggesting the override of the resolved value")
    func unbindInsideInstance() throws {
        let document = try PlannerFixture.document()
        try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Chi01", descendantID: "Lbl01", properties: ["fill": "$brand"]
        )))
        let refusal = try #require(PlannerFixture.refusal(.unbind(property: "kind.fills"), at: "Board/Chip/Label", in: document))

        #expect(refusal.code == .setInsideInstance)
        #expect(refusal.suggestion == "fill=#E5484D")
    }

    @Test("An unbind writes the value the variable resolves to")
    func unbind() throws {
        let document = try PlannerFixture.document()
        let plan = try plan(.unbind(property: "kind.fills"), at: "Board/Row/Flow", in: document)

        #expect(plan.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Flo01", properties: ["kind.fills": "#E5484D"])),
        ])
    }

    @Test("An unbind of a themed variable writes the value under the node's theme")
    func unbindThemed() throws {
        let document = try PlannerFixture.document()
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Brd01", properties: ["common.theme": ["mode": "dark"]]
        )))
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Flo01", properties: ["kind.fills": "$ink"]
        )))
        let plan = try plan(.unbind(property: "kind.fills"), at: "Board/Row/Flow", in: document)

        #expect(plan.operations == [
            .setProperties(EditOperation.SetProperties(nodeID: "Flo01", properties: ["kind.fills": "#EEEEEE"])),
        ])
    }

    @Test("An unbind of a property holding no binding is refused with notBound")
    func unbindUnbound() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(.unbind(property: "kind.fills"), at: "Board/Chip/Label", in: document))

        #expect(refusal.code == .notBound)
        #expect(refusal.property == "kind.fills")
    }
}
