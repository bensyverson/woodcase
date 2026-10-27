//
//  NestedDetachFixture.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// An instance holding nested instances, for the detach suites (leaf DbitT1).
///
/// - `Jewel` (`jewel`) holds `Facet` (`facet`).
/// - `Kit` is a plain frame holding two components: `Dot` (`dot`), which holds `Pip`
///   (`pip`) and `Gem` (`gem`, an instance of `Jewel`), and `Button` (`button`), which
///   holds `Label` (`label`) and `Badge` (`badge`, an instance of `Dot`).
/// - `ok` places `Button` and overrides inside it at every depth: its own `label`, the
///   nested instance `badge` itself (`opacity`, and `width` on its root), `badge/pip` one
///   instance down and `badge/gem/facet` two down.
/// - `Loose` is a rectangle the connectors end at: `KRoot` from `ok`, `KPip` from
///   `ok/badge/pip`, `KFacet` from `ok/badge/gem/facet`.
enum NestedDetachFixture {
    /// The fixture's JSON.
    static let json = """
    {"version": "2.19", "children": [
      {"id": "jewel", "type": "frame", "name": "Jewel", "reusable": true, "x": 0, "y": 400,
       "width": 10, "height": 10, "layout": "none", "children": [
        {"id": "facet", "type": "rectangle", "name": "Facet", "width": 4, "height": 4, "fill": "#111111"}]},
      {"id": "Kit", "type": "frame", "name": "Kit", "x": 0, "y": 0, "width": 400, "height": 200,
       "layout": "none", "children": [
        {"id": "dot", "type": "frame", "name": "Dot", "reusable": true, "x": 0, "y": 0,
         "width": 20, "height": 20, "layout": "none", "children": [
          {"id": "pip", "type": "rectangle", "name": "Pip", "x": 2, "y": 2, "width": 8, "height": 8, "fill": "#000000"},
          {"id": "gem", "type": "ref", "ref": "jewel", "name": "Gem", "x": 10, "y": 10}]},
        {"id": "button", "type": "frame", "name": "Button", "reusable": true, "x": 100, "y": 0,
         "width": 120, "height": 40, "layout": "horizontal", "children": [
          {"id": "label", "type": "text", "name": "Label", "content": "OK"},
          {"id": "badge", "type": "ref", "ref": "dot", "name": "Badge"}]}]},
      {"id": "ok", "type": "ref", "ref": "button", "name": "OK Button", "x": 300, "y": 300,
       "descendants": {
         "label": {"content": "Okay"},
         "badge": {"opacity": 0.5, "width": 30},
         "badge/pip": {"fill": "#F59E0B"},
         "badge/gem/facet": {"fill": "#22C55E"}}},
      {"id": "Loose", "type": "rectangle", "name": "Loose", "x": 0, "y": 600, "width": 10, "height": 10},
      {"id": "KRoot", "type": "connection", "source": {"path": "ok", "anchor": "right"},
       "target": {"path": "Loose", "anchor": "left"}},
      {"id": "KPip", "type": "connection", "source": {"path": "ok/badge/pip", "anchor": "right"},
       "target": {"path": "Loose", "anchor": "left"}},
      {"id": "KFacet", "type": "connection", "source": {"path": "ok/badge/gem/facet", "anchor": "right"},
       "target": {"path": "Loose", "anchor": "left"}}
    ]}
    """

    /// The fixture, parsed.
    static func parsed() throws -> PenDocument {
        try PenParser.parse(Data(json.utf8))
    }

    /// A fresh editable copy of the fixture.
    static func document() throws -> EditableDocument {
        try EditableDocument(from: parsed())
    }

    /// A connector's source path.
    static func source(of connectorID: String, in document: EditableDocument) -> String? {
        ConnectorFixture.ends(of: document.nodes[connectorID])?.first
    }

    /// The refs left in the document, by id → the component each names.
    static func refs(in document: EditableDocument) -> [String: String] {
        document.nodes.compactMapValues { node in
            guard case let .ref(data) = node.kind else { return nil }
            return data.ref
        }
    }

    /// The fill a rectangle of the canvas expansion draws with, or `nil`.
    static func fill(of expandedID: String, in document: EditableDocument) -> PenFills? {
        var pending = PenRefExpander.expand(document.materialize(), for: .canvas).children
        while let node = pending.popLast() {
            if node.id == expandedID {
                guard case let .rectangle(data) = node.kind else { return nil }
                return data.fills
            }
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return nil
    }

    /// A fill written as a hex color, decoded as the file would be.
    static func color(_ hex: String) throws -> PenFills {
        try JSONDecoder().decode(PenFills.self, from: Data("\"\(hex)\"".utf8))
    }
}
