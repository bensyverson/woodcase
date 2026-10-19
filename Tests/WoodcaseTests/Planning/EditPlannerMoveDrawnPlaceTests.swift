//
//  EditPlannerMoveDrawnPlaceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A move that keeps the node's drawn place
/// (``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:in:layout:)``): where the new
/// parent places the node by position, its `x`/`y`, rotation and flips are rewritten
/// together, so it is drawn where it was, moved by the offset — whatever the parents' turns
/// and flips (Penumbra issue qIds8z).
@MainActor
struct EditPlannerMoveDrawnPlaceTests {
    /// `Plain` is an unturned free frame holding `Chip` (unturned) and `Leaning` (turned
    /// 10°); `Turned` a free frame turned 30° holding `Inside`; `Mirror` a free frame turned
    /// 30° and flipped left to right; `Stack` a vertical stack holding `Pinned`, an absolute
    /// child.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Plain", "x": 0, "y": 0, "width": 400, "height": 300, "layout": "none",
          "children": [
          { "type": "rectangle", "id": "Chip", "x": 20, "y": 30, "width": 40, "height": 20 },
          { "type": "rectangle", "id": "Leaning", "x": 100, "y": 120, "width": 30, "height": 50, "rotation": 10 }
        ] },
        { "type": "frame", "id": "Turned", "x": 500, "y": 0, "width": 200, "height": 200, "layout": "none",
          "rotation": 30, "children": [
          { "type": "rectangle", "id": "Inside", "x": 10, "y": 10, "width": 30, "height": 30 }
        ] },
        { "type": "frame", "id": "Mirror", "x": 0, "y": 400, "width": 200, "height": 200, "layout": "none",
          "rotation": 30, "flipX": true, "children": [] },
        { "type": "frame", "id": "Stack", "x": 500, "y": 400, "width": 200, "height": "fit_content",
          "layout": "vertical", "gap": 8, "padding": 8, "children": [
          { "type": "rectangle", "id": "Flow", "width": 40, "height": 20 },
          { "type": "rectangle", "id": "Pinned", "x": 4, "y": 4, "width": 20, "height": 20,
            "layoutPosition": "absolute" }
        ] }
      ]
    }
    """

    /// The offset every drop is carried by.
    private static let offset = PenPoint(x: 12, y: -7)

    /// Plans a move keeping the drawn place, applies it, and returns the node's canvas quad
    /// before (moved by `offset`) and after.
    private func move(
        _ id: String, into parent: String?, by offset: PenPoint = offset, in document: EditableDocument
    ) throws -> (expected: [PenPoint], drawn: [PenPoint]) {
        let before = try #require(WrapFixture.corners(of: id, in: document, layout: WrapFixture.layout(of: document)))
        let operations = try EditPlanner.planMove(
            nodeID: id, into: parent, keepingDrawnPlace: offset, in: document, layout: WrapFixture.layout(of: document)
        )
        try WrapFixture.apply(operations, to: document)
        #expect(document.parentID(of: id) == parent)
        let after = try #require(WrapFixture.corners(of: id, in: document, layout: WrapFixture.layout(of: document)))
        return (before.map { PenPoint(x: $0.x + offset.x, y: $0.y + offset.y) }, after)
    }

    /// A node's stored literal rotation, `0` when it stores none.
    private func rotation(of id: String, in document: EditableDocument) -> Double? {
        let stored = document.node(id: id)?.common.rotation
        return stored == nil ? 0 : stored?.literalValue
    }

    @Test("An unturned node moved into a parent turned 30° is turned −30°, drawn where it was dropped")
    func intoATurnedParent() throws {
        let document = try WrapFixture.document(Self.json)
        let quads = try move("Chip", into: "Turned", in: document)
        #expect(WrapFixture.same(quads.expected, quads.drawn), "\(quads)")
        #expect(try abs(#require(rotation(of: "Chip", in: document)) + 30) < 1e-6)
    }

    @Test("A node moved out of a parent turned 30° onto the canvas is turned 30°, drawn where it was dropped")
    func outOfATurnedParent() throws {
        let document = try WrapFixture.document(Self.json)
        let quads = try move("Inside", into: nil, in: document)
        #expect(WrapFixture.same(quads.expected, quads.drawn), "\(quads)")
        #expect(try abs(#require(rotation(of: "Inside", in: document)) - 30) < 1e-6)
    }

    @Test("Into a flipped parent the turn's sense reverses and the flip toggles: not old + old turn − new turn")
    func intoAFlippedParent() throws {
        let document = try WrapFixture.document(Self.json)
        let quads = try move("Leaning", into: "Mirror", in: document)
        #expect(WrapFixture.same(quads.expected, quads.drawn), "\(quads)")
        let node = try #require(document.node(id: "Leaning"))
        #expect(node.common.flipX?.literalValue == true)
        // Mirror's map is turn(30) · flip, so the child's own turn r draws as turn(30 − r):
        // 30 − r = 10 gives r = 20, where the naive 10 + 0 − 30 would give −20.
        #expect(try abs(#require(rotation(of: "Leaning", in: document)) - 20) < 1e-6)
    }

    @Test("Carried within the same turned parent, only x and y are written, by the offset turned into it")
    func withinATurnedParent() throws {
        let document = try WrapFixture.document(Self.json)
        let operations = try EditPlanner.planMove(
            nodeID: "Inside", into: "Turned", keepingDrawnPlace: Self.offset, in: document,
            layout: WrapFixture.layout(of: document)
        )
        guard operations.count == 2, case let .setProperties(write) = operations[1] else {
            Issue.record("expected the move and one write: \(operations)")
            return
        }
        #expect(Set(write.properties.keys) == ["common.x", "common.y"])
        let carried = try WrapFixture.document(Self.json)
        let quads = try move("Inside", into: "Turned", in: carried)
        #expect(WrapFixture.same(quads.expected, quads.drawn), "\(quads)")
    }

    @Test("Between unturned parents only x and y change, by the offset in the new parent's coordinates")
    func betweenPlainParents() throws {
        let plain = try WrapFixture.document(Self.json)
        let quads = try move("Chip", into: nil, in: plain)
        #expect(WrapFixture.same(quads.expected, quads.drawn), "\(quads)")
        let chip = try #require(plain.node(id: "Chip"))
        #expect(chip.common.x?.literalValue == 32)
        #expect(chip.common.y?.literalValue == 23)
        #expect(chip.common.rotation == nil)
    }

    @Test("An absolute child keeps its drawn place leaving a stack and entering one, and stays absolute there")
    func absoluteIntoAStack() throws {
        let document = try WrapFixture.document(Self.json)
        let quads = try move("Pinned", into: "Plain", in: document)
        #expect(WrapFixture.same(quads.expected, quads.drawn), "\(quads)")

        let back = try WrapFixture.document(Self.json)
        try WrapFixture.apply(
            [.setProperties(EditOperation.SetProperties(nodeID: "Chip", properties: ["common.layoutPosition": "absolute"]))],
            to: back
        )
        let pinned = try move("Chip", into: "Stack", in: back)
        #expect(WrapFixture.same(pinned.expected, pinned.drawn), "\(pinned)")
        #expect(back.node(id: "Chip")?.common.layoutPosition == .absolute)
    }

    @Test("A flow child moved into a stack ignores the offset: the stack places it")
    func flowIntoAStack() throws {
        let document = try WrapFixture.document(Self.json)
        let operations = try EditPlanner.planMove(
            nodeID: "Chip", into: "Stack", at: 0, keepingDrawnPlace: Self.offset, in: document,
            layout: WrapFixture.layout(of: document)
        )
        #expect(operations == [.moveNode(EditOperation.MoveNode(nodeID: "Chip", newParentID: "Stack", index: 0))])
    }
}
