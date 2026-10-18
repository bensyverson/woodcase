//
//  DefaultTextStyleFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// A document for the default text style's tests: the mark planner and the queries an
/// editor reads the default from (Penumbra spec §6.3, Ben's ruling of 2026-10-18).
///
/// `Page` holds `Title` (family bound to `$display`), `Inner` (a frame holding `Deep`,
/// whose family is bound to `$abc`, a number variable) and `Body` (family bound to
/// `$body`); `Shape` is a rectangle; `Sticky` is a note whose family is bound to `$aaa`;
/// `Chip` is an instance of `Card`, a component whose `Label` is a text. `brandFont` and
/// `zzz` are string variables nothing binds, and `brandFont`'s value looks like a font.
enum DefaultTextStyleFixture {
    /// The fixture's JSON.
    static let json = """
    {
      "version": "2.19",
      "variables": {
        "aaa": { "type": "string", "value": "Courier" },
        "abc": { "type": "number", "value": 3 },
        "accent": { "type": "color", "value": "#FF0000" },
        "body": { "type": "string", "value": "Inter" },
        "brandFont": { "type": "string", "value": "Helvetica" },
        "display": { "type": "string", "value": "Georgia" },
        "zzz": { "type": "string", "value": "Menlo" }
      },
      "children": [
        { "type": "frame", "id": "Page", "x": 0, "y": 0, "width": 400, "height": 400, "layout": "none", "children": [
          { "type": "text", "id": "Title", "x": 0, "y": 0, "content": "Title", "fontFamily": "$display" },
          { "type": "frame", "id": "Inner", "x": 0, "y": 40, "width": 200, "height": 100, "layout": "none",
            "children": [
            { "type": "text", "id": "Deep", "x": 0, "y": 0, "content": "Deep", "fontFamily": "$abc" }
          ] },
          { "type": "text", "id": "Body", "x": 0, "y": 200, "content": "Body", "fontFamily": "$body" }
        ] },
        { "type": "rectangle", "id": "Shape", "x": 500, "y": 0, "width": 40, "height": 40 },
        { "type": "note", "id": "Sticky", "x": 600, "y": 0, "width": 100, "height": 100, "content": "Hi",
          "fontFamily": "$aaa" },
        { "type": "ref", "id": "Chip", "ref": "Card", "x": 900, "y": 0 },
        { "type": "frame", "id": "Card", "reusable": true, "x": 900, "y": 200, "width": 120, "height": 60,
          "layout": "none", "children": [
          { "type": "text", "id": "Label", "x": 4, "y": 4, "content": "Hi" }
        ] }
      ]
    }
    """

    /// The key's deep path, `common.metadata.woodcase.defaultTextStyle`.
    static let path = PenMetadata.WoodcaseKey.defaultTextStyle.path

    /// A fresh copy of the fixture.
    static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    /// Writes the key on each node through the planner, as any set is written.
    static func write(_ value: AnyCodable, on ids: [String], in document: EditableDocument) throws {
        for id in ids {
            let plan = try EditPlanner.plan(.set([path: value]), at: PlannerFixture.address("#\(id)"), in: document)
            try apply(plan.operations, to: document)
        }
    }

    /// Applies operations in order.
    static func apply(_ operations: [EditOperation], to document: EditableDocument) throws {
        for operation in operations {
            try document.apply(operation)
        }
    }

    /// The nodes the operations write, when every one is a property write; `nil` otherwise.
    static func written(by operations: [EditOperation]) -> Set<String>? {
        var ids: Set<String> = []
        for operation in operations {
            guard case let .setProperties(write) = operation else { return nil }
            ids.insert(write.nodeID)
        }
        return ids
    }

    /// The ids holding the mark, in document order.
    static func marked(in document: EditableDocument) -> [String] {
        document.nodeIDsInDocumentOrder().filter {
            document.node(id: $0)?.common.metadata?[woodcase: .defaultTextStyle] == .bool(true)
        }
    }

    /// The refusal a mark plan throws, or `nil` when it plans.
    static func markRefusal(_ id: String, in document: EditableDocument) -> EditRefusal? {
        do {
            _ = try EditPlanner.planMarkDefaultTextStyle(nodeID: id, in: document)
            return nil
        } catch {
            return error
        }
    }
}
