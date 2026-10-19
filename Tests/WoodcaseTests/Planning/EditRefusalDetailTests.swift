//
//  EditRefusalDetailTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a refusal carries beyond its sentence (``EditRefusal/detail``): the loop a move
/// would close, the component whose instances a removal would orphan, the candidates an
/// address could mean — each under its own ``EditRefusal/Code``, so an editor branches and
/// names things without matching strings or replaying the edit.
@MainActor
struct EditRefusalDetailTests {
    /// `Card` (named "Profile card") renders `Badge` (named "Status badge") through
    /// `BadgeUse`; `CardUse` is a free instance of `Card` on the canvas, `Box` a free frame
    /// holding `Dot`, a frame.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Card", "name": "Profile card", "reusable": true, "x": 0, "y": 0,
          "width": 120, "height": 60, "layout": "none", "children": [
          { "type": "ref", "id": "BadgeUse", "ref": "Badge", "x": 4, "y": 4 }
        ] },
        { "type": "frame", "id": "Badge", "name": "Status badge", "reusable": true, "x": 0, "y": 200,
          "width": 40, "height": 20, "layout": "none", "children": [] },
        { "type": "ref", "id": "CardUse", "ref": "Card", "x": 300, "y": 0 },
        { "type": "frame", "id": "Box", "x": 0, "y": 400, "width": 100, "height": 100, "layout": "none",
          "children": [
          { "type": "frame", "id": "Dot", "x": 0, "y": 0, "width": 10, "height": 10, "layout": "none" }
        ] }
      ]
    }
    """

    /// The refusal a move plan throws, or `nil` when it plans.
    private func moveRefusal(_ id: String, into parent: String?, in document: EditableDocument) -> EditRefusal? {
        do {
            _ = try EditPlanner.planMove(nodeID: id, into: parent, in: document, layout: WrapFixture.layout(of: document))
            return nil
        } catch {
            return error
        }
    }

    @Test("A move closing a loop names it by component, in render order, with display names")
    func moveLoop() throws {
        let document = try WrapFixture.document(Self.json)
        let refusal = try #require(moveRefusal("CardUse", into: "Badge", in: document))

        #expect(refusal.code == .wouldCloseComponentLoop)
        #expect(refusal.errorCode == "wouldCloseComponentLoop")
        #expect(refusal.detail == .componentLoop(ComponentLoop(members: [
            ComponentLoop.Member(id: "Badge", name: "Status badge"),
            ComponentLoop.Member(id: "Card", name: "Profile card"),
        ])))
        #expect(!refusal.message.isEmpty)
    }

    @Test("A group closing a loop carries the loop, with a component's id where it has no name")
    func groupLoop() throws {
        let document = try WrapFixture.document()
        let refusal = try #require(WrapFixture.groupRefusal(["Chip", "Slot"], in: document))

        #expect(refusal.code == .wouldCloseComponentLoop)
        #expect(refusal.detail == .componentLoop(ComponentLoop(members: [
            ComponentLoop.Member(id: "Card", name: "Card"),
        ])))
    }

    @Test("Ungrouping a component with instances names the component and its instances")
    func ungroupComponentWithInstances() throws {
        let document = try WrapFixture.document(Self.json)
        let refusal = try #require(WrapFixture.ungroupRefusal("Badge", in: document))

        #expect(refusal.code == .componentHasInstances)
        #expect(refusal.errorCode == "componentHasInstances")
        #expect(refusal.detail == .componentHasInstances(componentID: "Badge", instanceIDs: ["BadgeUse"]))
    }

    @Test("A move into the node's own descendant names the node and the parent")
    func moveIntoDescendant() throws {
        let document = try WrapFixture.document(Self.json)
        let refusal = try #require(moveRefusal("Box", into: "Dot", in: document))

        #expect(refusal.code == .wouldCreateCycle)
        #expect(refusal.detail == .wouldCreateCycle(nodeID: "Box", targetParentID: "Dot"))
    }

    @Test("An address naming nothing carries the near misses")
    func addressNearMisses() throws {
        let document = try PlannerFixture.document()
        let refusal = try #require(PlannerFixture.refusal(.set(["common.opacity": 1]), at: "Nope/Label", in: document))

        #expect(refusal.code == .addressNotFound)
        guard case let .candidates(candidates)? = refusal.detail else {
            Issue.record("no candidates: \(String(describing: refusal.detail))")
            return
        }
        #expect(candidates.contains { $0.id == "Lbl01" })
    }
}
