//
//  EditPlannerUngroupTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Ungroup (``EditPlanner/planUngroup(groupID:in:layout:)``): the children go to the
/// group's parent at its index, in their order, with the group's position, turn and flips
/// folded into each, so every one keeps the quad it is drawn as; in a stack they join the
/// flow there (Penumbra spec §14, the integrator's ruling of 2026-10-15).
@MainActor
struct EditPlannerUngroupTests {
    /// A turned, flipped group inside a turned, flipped group, and a turned stack frame.
    private static let nested = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 800, "height": 600, "layout": "none", "children": [
          { "type": "rectangle", "id": "Back", "x": 0, "y": 0, "width": 10, "height": 10 },
          { "type": "group", "id": "Outer", "x": 200, "y": 150, "rotation": -40, "flipY": true, "children": [
            { "type": "group", "id": "Inner", "x": 30, "y": 20, "rotation": 25, "flipX": true, "children": [
              { "type": "rectangle", "id": "I1", "x": -10, "y": 5, "width": 40, "height": 16, "rotation": 10 },
              { "type": "ellipse", "id": "I2", "x": 50, "y": 30, "width": 20, "height": 30, "flipY": true }
            ] },
            { "type": "rectangle", "id": "O2", "x": 80, "y": 0, "width": 20, "height": 20 }
          ] },
          { "type": "frame", "id": "Panel", "x": 500, "y": 100, "width": 120, "height": "fit_content",
            "rotation": 20, "layout": "vertical", "gap": 6, "padding": 10, "children": [
            { "type": "rectangle", "id": "P1", "width": "fill_container", "height": 20 },
            { "type": "rectangle", "id": "P2", "width": 40, "height": 30 }
          ] },
          { "type": "rectangle", "id": "Top", "x": 700, "y": 500, "width": 10, "height": 10 }
        ] }
      ]
    }
    """

    /// A vertical stack holding a group whose children sit where the flow would put them.
    private static let stacked = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Stack", "x": 40, "y": 40, "width": 100, "height": "fit_content",
          "layout": "vertical", "children": [
          { "type": "rectangle", "id": "Head", "width": 100, "height": 20 },
          { "type": "group", "id": "Pair", "children": [
            { "type": "rectangle", "id": "G1", "x": 0, "y": 0, "width": 60, "height": 10 },
            { "type": "rectangle", "id": "G2", "x": 0, "y": 10, "width": 80, "height": 15 }
          ] },
          { "type": "rectangle", "id": "Tail", "width": 100, "height": 20 }
        ] }
      ]
    }
    """

    /// Plans and applies an ungroup, returning what moved on the canvas.
    private func ungroup(_ id: String, in document: EditableDocument, watching ids: [String]) throws -> [String] {
        let before = WrapFixture.quads(ids, in: document)
        let operations = try EditPlanner.planUngroup(
            groupID: id, in: document, layout: WrapFixture.layout(of: document)
        )
        try WrapFixture.apply(operations, to: document)
        #expect(document.node(id: id) == nil, "the group is still there")
        return WrapFixture.moved(before, WrapFixture.quads(ids, in: document))
    }

    @Test("A turned, flipped group inside a turned, flipped group: its children keep their quads")
    func nestedTurnedFlipped() throws {
        let document = try WrapFixture.document(Self.nested)
        let moved = try ungroup("Inner", in: document, watching: ["I1", "I2", "O2"])

        #expect(moved.isEmpty, "moved: \(moved)")
        #expect(document.childIDs(of: "Outer") == ["I1", "I2", "O2"])
    }

    @Test("Ungrouping to the board folds a turned, flipped group into each child")
    func toTheBoard() throws {
        let document = try WrapFixture.document(Self.nested)
        let moved = try ungroup("Outer", in: document, watching: ["I1", "I2", "O2"])

        #expect(moved.isEmpty, "moved: \(moved)")
        #expect(document.childIDs(of: "Board") == ["Back", "Inner", "O2", "Panel", "Top"])
        let o2 = try #require(document.node(id: "O2"))
        // −40° and a top-to-bottom flip: the flip stays, the turn is folded in.
        #expect(o2.common.flipY == .literal(true))
        #expect(o2.common.rotation == .literal(-40))
    }

    @Test("Ungrouping a turned stack frame frees its flow children where they were drawn")
    func frameStack() throws {
        let document = try WrapFixture.document(Self.nested)
        let moved = try ungroup("Panel", in: document, watching: ["P1", "P2"])

        #expect(moved.isEmpty, "moved: \(moved)")
        #expect(document.childIDs(of: "Board") == ["Back", "Outer", "P1", "P2", "Top"])
        let p1 = try #require(document.node(id: "P1"))
        #expect(try NodePropertyCodec.value(at: "kind.width", of: p1) == .int(100))
        #expect(p1.common.rotation == .literal(20))
    }

    @Test("In a stack, the children join the flow at the group's index")
    func intoAStack() throws {
        let document = try WrapFixture.document(Self.stacked)
        let moved = try ungroup("Pair", in: document, watching: ["Head", "G1", "G2", "Tail"])

        #expect(moved.isEmpty, "moved: \(moved)")
        #expect(document.childIDs(of: "Stack") == ["Head", "G1", "G2", "Tail"])
        let g2 = try #require(document.node(id: "G2"))
        #expect(g2.common.x == nil && g2.common.y == nil)
    }

    @Test("A fill child joining a stack's flow keeps its fill, which the stack lays out")
    func fillJoinsAStack() throws {
        let json = Self.stacked.replacingOccurrences(
            of: #""id": "G2", "x": 0, "y": 10, "width": 80"#, with: #""id": "G2", "x": 0, "y": 10, "width": "fill_container""#
        )
        let document = try WrapFixture.document(json)
        let operations = try EditPlanner.planUngroup(groupID: "Pair", in: document, layout: WrapFixture.layout(of: document))
        try WrapFixture.apply(operations, to: document)
        let g2 = try #require(document.node(id: "G2"))
        #expect(try NodePropertyCodec.value(at: "kind.width", of: g2) == .string("fill_container"))
    }

    // MARK: - Refusals

    @Test("A node that is neither a group nor a frame is refused with notAGroup")
    func notAGroup() throws {
        let document = try WrapFixture.document()
        #expect(WrapFixture.ungroupRefusal("A", in: document)?.code == .notAGroup)
    }

    @Test("A frame inside an instance is refused with insideInstance")
    func insideInstance() throws {
        let document = try WrapFixture.document()
        let inside = document.expandedID(of: .instanceDescendant(refID: "Chip", descendantKey: "Slot"))
        #expect(WrapFixture.ungroupRefusal(inside, in: document)?.code == .insideInstance)
    }

    @Test("An id naming no node is refused with addressNotFound")
    func unknownID() throws {
        let document = try WrapFixture.document()
        #expect(WrapFixture.ungroupRefusal("Nope", in: document)?.code == .addressNotFound)
    }
}
