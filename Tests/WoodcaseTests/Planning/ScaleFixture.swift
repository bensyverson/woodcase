//
//  ScaleFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// A document for the proportional-scale tests (``ScaleCapture``), and the helpers they
/// judge it by.
///
/// `Board` is a free frame holding:
/// - `Card`, a vertical stack with every scaled frame property: gap, `[v, h]` padding,
///   per-corner radii, a per-side stroke, a shadow (with a spread), a layer blur and a
///   background blur. Its children are in flow: `Title` (an `auto` text with a size, letter
///   spacing, a line-height multiple and a run with a size of its own), `Body` (a
///   `fixed-width` text) and `Boxed` (a `fixed-width-height` text with no size, so 16);
/// - `Dashed`, a free rectangle with a uniform stroke, a radius and a dash;
/// - `Wave`, a free path;
/// - `Turned`, a group at `(600, 200)` turned 30° and flipped, holding `T1`, `T2` (turned
///   −20° and flipped) and `T3`;
/// - `Sticky`, a note with a 14 pt type size and no size of its own (200 × 200);
/// - `Chip`, an instance of `Button`;
/// - `Bound`, a frame whose gap and padding are bound to `$pad`.
///
/// `Button` is a component: a horizontal stack (gap 4, padding 8, radius 8) holding the
/// text `Label` (14 pt).
enum ScaleFixture {
    /// The fixture's JSON.
    static let json = """
    {
      "version": "2.19",
      "variables": { "pad": { "type": "number", "value": 12 } },
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 1000, "height": 800, "layout": "none", "children": [
          { "type": "frame", "id": "Card", "x": 100, "y": 50, "width": 200, "height": 120,
            "layout": "vertical", "gap": 8, "padding": [10, 12], "cornerRadius": [4, 6, 8, 10],
            "stroke": "#000000", "strokeWidth": { "top": 1, "right": 2, "bottom": 3, "left": 4 },
            "effect": [
              { "type": "shadow", "shadowType": "outer", "offset": { "x": 2, "y": 4 }, "blur": 6, "color": "#00000040" },
              { "type": "blur", "radius": 3 },
              { "type": "background_blur", "radius": 5 }
            ],
            "metadata": { "type": "woodcase", "woodcase": { "shadowSpread": [ { "effect": 0, "spread": 2,
              "shadow": { "type": "shadow", "shadowType": "outer", "offset": { "x": 2, "y": 4 }, "blur": 6,
                          "color": "#00000040" } } ] } },
            "children": [
            { "type": "text", "id": "Title", "content": "Hello", "fontSize": 20, "letterSpacing": 1.5,
              "lineHeight": 1.2, "textGrowth": "auto",
              "metadata": { "type": "woodcase", "woodcase": { "spans": { "text": "Hello",
                "runs": [ { "start": 0, "end": 2, "fontSize": 30 } ] } } } },
            { "type": "text", "id": "Body", "content": "Wrapped words", "fontSize": 12, "textGrowth": "fixed-width",
              "width": 150 },
            { "type": "text", "id": "Boxed", "content": "Box", "textGrowth": "fixed-width-height",
              "width": 80, "height": 40 }
          ] },
          { "type": "rectangle", "id": "Dashed", "x": 400, "y": 300, "width": 50, "height": 30, "cornerRadius": 5,
            "stroke": "#000000", "strokeWidth": 2,
            "metadata": { "type": "woodcase", "woodcase": { "strokeDash": [4, 2], "strokeDashOffset": 1 } } },
          { "type": "path", "id": "Wave", "x": 500, "y": 100, "width": 10, "height": 10, "geometry": "M0 0 L10 10" },
          { "type": "group", "id": "Turned", "x": 600, "y": 200, "rotation": 30, "flipX": true, "children": [
            { "type": "rectangle", "id": "T1", "x": 0, "y": 0, "width": 40, "height": 20 },
            { "type": "rectangle", "id": "T2", "x": 60, "y": 10, "width": 20, "height": 30,
              "rotation": -20, "flipY": true },
            { "type": "rectangle", "id": "T3", "x": 10, "y": 50, "width": 25, "height": 25 }
          ] },
          { "type": "note", "id": "Sticky", "x": 700, "y": 500, "content": "Hi",
            "metadata": { "type": "woodcase", "woodcase": { "fontSize": 14 } } },
          { "type": "ref", "id": "Chip", "ref": "Button", "x": 50, "y": 600 },
          { "type": "frame", "id": "Bound", "x": 800, "y": 50, "width": 100, "height": 100,
            "layout": "vertical", "gap": "$pad", "padding": "$pad" }
        ] },
        { "type": "frame", "id": "Button", "reusable": true, "x": 0, "y": 1000, "width": 120, "height": 40,
          "layout": "horizontal", "gap": 4, "padding": 8, "cornerRadius": 8, "children": [
          { "type": "text", "id": "Label", "content": "Go", "fontSize": 14 }
        ] }
      ]
    }
    """

    /// A fresh copy of the fixture.
    static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    /// A full layout of the document as it stands.
    static func layout(of document: EditableDocument) -> PenLayoutState {
        PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
    }

    /// Captures `ids` and plans a scale by `factor` about `anchor`.
    static func plan(
        _ ids: [String], by factor: Double, anchor: ScaleAnchor = .topLeft, in document: EditableDocument
    ) throws -> ScalePlan {
        let capture = try ScaleCapture(nodeIDs: ids, in: document, layout: layout(of: document))
        return try capture.plan(factor: factor, anchor: anchor, in: document)
    }

    /// Plans a scale and applies it.
    @discardableResult
    static func scale(
        _ ids: [String], by factor: Double, anchor: ScaleAnchor = .topLeft, in document: EditableDocument
    ) throws -> ScalePlan {
        let plan = try plan(ids, by: factor, anchor: anchor, in: document)
        for operation in plan.operations {
            try document.apply(operation)
        }
        return plan
    }

    /// A property of a stored node, as the file holds it.
    static func value(_ path: String, of id: String, in document: EditableDocument) throws -> AnyCodable {
        guard let node = document.node(id: id) else { return .null }
        return try NodePropertyCodec.value(at: path, of: node)
    }

    /// The quad a node of the expanded document is drawn as on the canvas.
    static func corners(ofExpanded id: String, in document: EditableDocument) -> [PenPoint]? {
        let layout = layout(of: document)
        return PenLayoutEngine.canvasPlacement(of: id, in: layout.document, layoutRects: layout.rects)?.corners
    }

    /// Whether `after` is `before` scaled by `factor` about `anchor`, corner for corner, to
    /// a hundredth of a point.
    static func isScaled(
        _ before: [PenPoint]?, to after: [PenPoint]?, by factor: Double, about anchor: PenPoint
    ) -> Bool {
        guard let before, let after, before.count == after.count else { return false }
        return zip(before, after).allSatisfy { old, new in
            let expected = PenPoint(x: anchor.x + factor * (old.x - anchor.x), y: anchor.y + factor * (old.y - anchor.y))
            return abs(expected.x - new.x) < 0.02 && abs(expected.y - new.y) < 0.02
        }
    }
}
