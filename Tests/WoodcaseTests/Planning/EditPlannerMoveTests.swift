//
//  EditPlannerMoveTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A move to another parent (``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)``): a node
/// whose new parent does not lay it out keeps the size it was drawn at, so each
/// `fill_container` dimension becomes that number; a `fit_content` one stays, and a stack
/// fills it on both axes, so moving into one changes nothing (Penumbra spec §4.4, Ben's
/// ruling of 2026-10-15, leaf skbh2k).
@MainActor
struct EditPlannerMoveTests {
    /// Penumbra's `reparent.pen` in miniature: `List`, a vertical stack 200 wide with
    /// padding 8, holds `Row` (fill width, 30 tall) and `Tall` (fill width, fit height,
    /// holding a 20-tall chip); `Board` is a free frame, `Wrap` a group, `Other` another
    /// stack; `Spare` is a free frame's child set absolute with a `fill_container(120)`
    /// width; `Badge` is a component and `Copy` its instance.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "List", "x": 0, "y": 400, "width": 200, "height": "fit_content",
          "layout": "vertical", "gap": 8, "padding": 8, "children": [
          { "type": "rectangle", "id": "Row", "width": "fill_container", "height": 30 },
          { "type": "frame", "id": "Tall", "width": "fill_container", "height": "fit_content",
            "layout": "horizontal", "children": [
            { "type": "rectangle", "id": "Chip", "width": 40, "height": 20 }
          ] }
        ] },
        { "type": "frame", "id": "Board", "x": 500, "y": 0, "width": 400, "height": 300, "layout": "none",
          "children": [
          { "type": "rectangle", "id": "Spare", "x": 10, "y": 10, "width": "fill_container(120)", "height": 10,
            "layoutPosition": "absolute" }
        ] },
        { "type": "group", "id": "Wrap", "x": 0, "y": 0, "children": [
          { "type": "rectangle", "id": "Dot", "x": 0, "y": 0, "width": 10, "height": 10 }
        ] },
        { "type": "frame", "id": "Other", "x": 0, "y": 700, "width": 300, "height": "fit_content",
          "layout": "vertical", "children": [] },
        { "type": "frame", "id": "Badge", "reusable": true, "x": 500, "y": 400, "width": 120, "height": 40,
          "layout": "none", "children": [] },
        { "type": "ref", "id": "Copy", "ref": "Badge", "x": 700, "y": 400 }
      ]
    }
    """

    /// Plans a move, applies it, and returns the moved node.
    private func move(_ id: String, into parent: String?, in document: EditableDocument) throws -> PenNode {
        let operations = try EditPlanner.planMove(
            nodeID: id, into: parent, in: document, layout: WrapFixture.layout(of: document)
        )
        try WrapFixture.apply(operations, to: document)
        #expect(document.parentID(of: id) == parent)
        return try #require(document.node(id: id))
    }

    private func value(_ path: String, of node: PenNode) throws -> AnyCodable {
        try NodePropertyCodec.value(at: path, of: node)
    }

    @Test("A fill width moved into a free frame becomes the width it was drawn at")
    func intoAFreeFrame() throws {
        let document = try WrapFixture.document(Self.json)
        let row = try move("Row", into: "Board", in: document)
        #expect(try value("kind.width", of: row) == .int(184))
        #expect(try value("kind.height", of: row) == .int(30))
    }

    @Test("A fill width moved to the top level, or into a group, becomes the width it was drawn at")
    func toTheTopAndIntoAGroup() throws {
        let top = try WrapFixture.document(Self.json)
        #expect(try value("kind.width", of: move("Row", into: nil, in: top)) == .int(184))
        let grouped = try WrapFixture.document(Self.json)
        #expect(try value("kind.width", of: move("Row", into: "Wrap", in: grouped)) == .int(184))
    }

    @Test("A fit_content dimension stays when its fill width is frozen")
    func fitContentStays() throws {
        let document = try WrapFixture.document(Self.json)
        let tall = try move("Tall", into: "Board", in: document)
        #expect(try value("kind.width", of: tall) == .int(184))
        #expect(try value("kind.height", of: tall) == .string("fit_content"))
    }

    @Test("A move into another stack keeps the fill: the stack fills it on both axes")
    func intoAStack() throws {
        let document = try WrapFixture.document(Self.json)
        let operations = try EditPlanner.planMove(
            nodeID: "Row", into: "Other", at: 0, in: document, layout: WrapFixture.layout(of: document)
        )
        #expect(operations == [.moveNode(EditOperation.MoveNode(nodeID: "Row", newParentID: "Other", index: 0))])
    }

    @Test("An absolute child moved into a stack is not laid out by it, so its fill is frozen")
    func absoluteIntoAStack() throws {
        let document = try WrapFixture.document(Self.json)
        let spare = try move("Spare", into: "Other", in: document)
        #expect(try value("kind.width", of: spare) == .int(120))
    }

    @Test("A move that would make a component contain itself is refused with wouldCloseComponentLoop")
    func componentLoop() throws {
        let document = try WrapFixture.document(Self.json)
        do {
            _ = try EditPlanner.planMove(
                nodeID: "Copy", into: "Badge", in: document, layout: WrapFixture.layout(of: document)
            )
            Issue.record("the move was planned")
        } catch {
            #expect(error.code == .wouldCloseComponentLoop)
        }
    }

    @Test("A batch mv line into a free frame freezes the fill width too")
    func batchMove() throws {
        let document = try WrapFixture.document(Self.json)
        let report = BatchApplier.apply(
            [.mv(BatchOperation.MoveOp(target: .path(["Row"]), parent: .path(["Board"])))], to: document
        )
        #expect(report.succeeded, "\(report)")
        let row = try #require(document.node(id: "Row"))
        #expect(try value("kind.width", of: row) == .int(184))
    }
}
