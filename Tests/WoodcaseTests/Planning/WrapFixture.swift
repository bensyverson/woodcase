//
//  WrapFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// A document for the group, frame-selection and ungroup planners' tests, and the canvas
/// geometry they are judged by.
///
/// `Board` is a free frame holding:
/// - `A` and `B`, free rectangles, `B` turned 15°;
/// - `Turned`, a group at `(300, 200)` turned 30° and flipped left to right, holding `T1`,
///   `T2` (turned −20° and flipped top to bottom) and `T3`;
/// - `Stack`, a vertical stack (gap 10, padding 8) holding `S1` (fill width), `S2` and
///   `S3`, all in flow;
/// - `Front`, a free rectangle flipped left to right, the board's last child.
///
/// `Chip` is an instance of `Card`, a component whose `Label` is a text and whose `Slot`
/// is an empty free frame; `Card` comes after `Chip`, so `Card`'s nodes are drawn on top.
enum WrapFixture {
    /// The fixture's JSON.
    static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 800, "height": 600, "layout": "none", "children": [
          { "type": "rectangle", "id": "A", "x": 20, "y": 30, "width": 40, "height": 20 },
          { "type": "rectangle", "id": "B", "x": 100, "y": 80, "width": 30, "height": 50, "rotation": 15 },
          { "type": "group", "id": "Turned", "x": 300, "y": 200, "rotation": 30, "flipX": true, "children": [
            { "type": "rectangle", "id": "T1", "x": 0, "y": 0, "width": 40, "height": 20 },
            { "type": "ellipse", "id": "T2", "x": 60, "y": 10, "width": 20, "height": 30,
              "rotation": -20, "flipY": true },
            { "type": "rectangle", "id": "T3", "x": 10, "y": 50, "width": 25, "height": 25 }
          ] },
          { "type": "frame", "id": "Stack", "x": 400, "y": 300, "width": 200, "height": "fit_content",
            "layout": "vertical", "gap": 10, "padding": 8, "children": [
            { "type": "rectangle", "id": "S1", "width": "fill_container", "height": 20 },
            { "type": "rectangle", "id": "S2", "width": 50, "height": 30 },
            { "type": "rectangle", "id": "S3", "width": 60, "height": 25 }
          ] },
          { "type": "rectangle", "id": "Front", "x": 500, "y": 50, "width": 30, "height": 30, "flipX": true }
        ] },
        { "type": "ref", "id": "Chip", "ref": "Card", "x": 900, "y": 0 },
        { "type": "frame", "id": "Card", "reusable": true, "x": 900, "y": 200, "width": 120, "height": 60,
          "layout": "none", "children": [
          { "type": "text", "id": "Label", "x": 4, "y": 4, "content": "Hi" },
          { "type": "frame", "id": "Slot", "x": 40, "y": 10, "width": 30, "height": 30, "layout": "none" }
        ] }
      ]
    }
    """

    /// A fresh copy of the fixture, or of another document.
    static func document(_ json: String = json) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    /// A full layout of the document as it stands.
    static func layout(of document: EditableDocument) -> PenLayoutState {
        PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
    }

    /// The quad a stored node is drawn as on the canvas, or `nil` when it is not laid out.
    static func corners(of id: String, in document: EditableDocument, layout: PenLayoutState) -> [PenPoint]? {
        let expanded = document.expandedID(of: .node(id: id))
        return PenLayoutEngine.canvasPlacement(of: expanded, in: layout.document, layoutRects: layout.rects)?.corners
    }

    /// Every named node's canvas quad.
    static func quads(_ ids: [String], in document: EditableDocument) -> [String: [PenPoint]] {
        let layout = layout(of: document)
        var quads: [String: [PenPoint]] = [:]
        for id in ids {
            quads[id] = corners(of: id, in: document, layout: layout)
        }
        return quads
    }

    /// Applies a plan's operations in order.
    static func apply(_ operations: [EditOperation], to document: EditableDocument) throws {
        for operation in operations {
            try document.apply(operation)
        }
    }

    /// Whether two quads are the same, corner for corner, to a thousandth of a point.
    static func same(_ lhs: [PenPoint]?, _ rhs: [PenPoint]?) -> Bool {
        guard let lhs, let rhs, lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { abs($0.x - $1.x) < 1e-3 && abs($0.y - $1.y) < 1e-3 }
    }

    /// The ids whose quads differ between two snapshots.
    static func moved(_ before: [String: [PenPoint]], _ after: [String: [PenPoint]]) -> [String] {
        before.keys.sorted().filter { !same(before[$0], after[$0]) }
    }

    /// The refusal a group plan throws, or `nil` when it plans.
    static func groupRefusal(_ ids: [String], kind: WrapKind = .group, in document: EditableDocument) -> EditRefusal? {
        do {
            _ = try EditPlanner.planGroup(nodeIDs: ids, kind: kind, in: document, layout: layout(of: document))
            return nil
        } catch {
            return error
        }
    }

    /// The refusal an ungroup plan throws, or `nil` when it plans.
    static func ungroupRefusal(_ id: String, in document: EditableDocument) -> EditRefusal? {
        do {
            _ = try EditPlanner.planUngroup(groupID: id, in: document, layout: layout(of: document))
            return nil
        } catch {
            return error
        }
    }
}
