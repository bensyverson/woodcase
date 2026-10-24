//
//  ConnectorFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// A document of connected cards, for the connector queries and the clipboard's
/// connector suites.
///
/// `Board`, a free frame, holds `CardA` (with `Title`), `CardB`, `CardC` and `Chip`, an
/// instance of `Comp`, whose child is `Label`. The connectors, all at the top level as Pen
/// keeps them:
///
/// - `KAB` `CardA` → `CardB`, stroked with `$line`;
/// - `KTB` `Title` → `CardB`;
/// - `KAC` `CardA` → `CardC`;
/// - `KChip` `Chip/Label` → `CardA`.
enum ConnectorFixture {
    /// The fixture's JSON.
    static let json = """
    {
      "version": "2.20",
      "variables": { "line": { "type": "color", "value": "#336699" } },
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 800, "height": 600, "layout": "none", "children": [
          { "type": "frame", "id": "CardA", "x": 20, "y": 20, "width": 200, "height": 100, "layout": "none", "children": [
            { "type": "text", "id": "Title", "x": 10, "y": 10, "content": "Hi" }
          ] },
          { "type": "rectangle", "id": "CardB", "x": 400, "y": 20, "width": 40, "height": 40 },
          { "type": "rectangle", "id": "CardC", "x": 400, "y": 300, "width": 40, "height": 40 },
          { "type": "ref", "id": "Chip", "ref": "Comp", "x": 600, "y": 400 }
        ] },
        { "type": "frame", "id": "Comp", "reusable": true, "x": 0, "y": 700, "width": 100, "height": 40,
          "layout": "none", "children": [
          { "type": "text", "id": "Label", "x": 4, "y": 4, "content": "L" }
        ] },
        { "type": "connection", "id": "KAB", "source": { "path": "CardA", "anchor": "right" },
          "target": { "path": "CardB", "anchor": "left" }, "stroke": "$line", "strokeWidth": 2 },
        { "type": "connection", "id": "KTB", "source": { "path": "Title", "anchor": "right" },
          "target": { "path": "CardB", "anchor": "bottom" } },
        { "type": "connection", "id": "KAC", "source": { "path": "CardA", "anchor": "bottom" },
          "target": { "path": "CardC", "anchor": "left" } },
        { "type": "connection", "id": "KChip", "source": { "path": "Chip/Label", "anchor": "top" },
          "target": { "path": "CardA", "anchor": "bottom" } }
      ]
    }
    """

    /// A fresh copy of the fixture.
    static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    /// A connection's two end paths, source first.
    static func ends(of node: PenNode?) -> [String]? {
        guard case let .connection(data)? = node?.kind else { return nil }
        return [data.source.path, data.target.path]
    }

    /// Whether an end path names a node of the document: a stored node, or one drawn
    /// inside an instance.
    static func resolves(_ path: String, in document: EditableDocument) -> Bool {
        document.nodes[path] != nil || document.resolve(expandedID: path) != nil
    }
}
