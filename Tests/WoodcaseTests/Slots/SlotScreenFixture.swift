//
//  SlotScreenFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The slot-editing fixture (Penumbra spec §13.5, leaf JSPfTF): a screen component with
/// a list slot, two item variants and an empty state.
///
/// - `Item/A` (`ItemA`, 40 tall) and `Item/B` (`ItemB`, 56 tall) are the item variants,
///   each a horizontal stack holding a `Label` text; `Empty State` (`EmptyState`) holds a
///   `Message` text.
/// - `Screen` is a vertical stack holding `Title` and `List`, a vertical stack slot
///   (gap 8) suggesting `ItemA`, `ItemB` and a missing `Gone`, whose default content is
///   `Empty1`, an instance of `Empty State`.
/// - `Default` places `Screen` and changes only the default content's message
///   (`Empty1/ETxt`); `Filled` fills `List` with `Row1` (A), `Row2` (B, its label
///   overridden) and `Row3` (A); `Emptied` fills it with nothing.
/// - `Panel` holds `PScr`, a `Screen` instance of its own, so `PanelInst` shows a slot of
///   a nested instance (`PanelInst/PScr/List`).
/// - `Host` has a free-standing `Body` slot; `HostInst` fills it with `Nest`, a `Screen`
///   instance that fills its own `List` with `NRow1` — a slot inside a fill.
/// - `Board` is a free frame holding `Loose`, a rectangle to drag in; `Stack` a vertical
///   stack holding `S1`; `Free` is a component with a free (`layout: none`) slot `Area`,
///   placed by `FreeInst`, which fills it with `Dot` at (5, 6).
enum SlotScreenFixture {
    /// The fixture's JSON.
    static let json = """
    {"version": "2.19", "children": [
      {"id": "ItemA", "type": "frame", "name": "Item/A", "reusable": true, "x": 0, "y": 0,
       "width": 200, "height": 40, "layout": "horizontal", "children": [
        {"id": "ALbl", "type": "text", "name": "Label", "content": "Item A"}]},
      {"id": "ItemB", "type": "frame", "name": "Item/B", "reusable": true, "x": 0, "y": 60,
       "width": 200, "height": 56, "layout": "horizontal", "children": [
        {"id": "BLbl", "type": "text", "name": "Label", "content": "Item B"}]},
      {"id": "EmptyState", "type": "frame", "name": "Empty State", "reusable": true, "x": 0, "y": 140,
       "width": 200, "height": 80, "layout": "vertical", "children": [
        {"id": "ETxt", "type": "text", "name": "Message", "content": "No items"}]},
      {"id": "Screen", "type": "frame", "name": "Screen", "reusable": true, "x": 300, "y": 0,
       "width": 240, "height": "fit_content", "layout": "vertical", "children": [
        {"id": "Title", "type": "text", "name": "Title", "content": "Inbox"},
        {"id": "List", "type": "frame", "name": "List", "slot": ["ItemA", "ItemB", "Gone"],
         "width": "fill_container", "height": "fit_content", "layout": "vertical", "gap": 8, "children": [
          {"id": "Empty1", "type": "ref", "ref": "EmptyState", "name": "Empty"}]}]},
      {"id": "Default", "type": "ref", "ref": "Screen", "name": "Default Screen", "x": 600, "y": 0,
       "descendants": {"Empty1/ETxt": {"content": "Nothing yet"}}},
      {"id": "Filled", "type": "ref", "ref": "Screen", "name": "Filled Screen", "x": 900, "y": 0,
       "descendants": {"List": {"children": [
         {"id": "Row1", "type": "ref", "ref": "ItemA", "name": "Row 1"},
         {"id": "Row2", "type": "ref", "ref": "ItemB", "name": "Row 2", "descendants": {"BLbl": {"content": "Second"}}},
         {"id": "Row3", "type": "ref", "ref": "ItemA", "name": "Row 3"}]}}},
      {"id": "Emptied", "type": "ref", "ref": "Screen", "name": "Emptied Screen", "x": 1200, "y": 0,
       "descendants": {"List": {"children": []}}},
      {"id": "Panel", "type": "frame", "name": "Panel", "reusable": true, "x": 1500, "y": 0,
       "width": 260, "height": "fit_content", "layout": "vertical", "children": [
        {"id": "PScr", "type": "ref", "ref": "Screen", "name": "Inner Screen"}]},
      {"id": "PanelInst", "type": "ref", "ref": "Panel", "name": "Panel Instance", "x": 1800, "y": 0},
      {"id": "Host", "type": "frame", "name": "Host", "reusable": true, "x": 0, "y": 900,
       "width": 300, "height": "fit_content", "layout": "vertical", "children": [
        {"id": "Body", "type": "frame", "name": "Body", "slot": [], "width": "fill_container",
         "height": "fit_content", "layout": "vertical"}]},
      {"id": "HostInst", "type": "ref", "ref": "Host", "name": "Host Instance", "x": 400, "y": 900,
       "descendants": {"Body": {"children": [
         {"id": "Nest", "type": "ref", "ref": "Screen", "name": "Nested Screen", "descendants": {"List": {"children": [
           {"id": "NRow1", "type": "ref", "ref": "ItemA", "name": "Nested Row"}]}}}]}}},
      {"id": "Free", "type": "frame", "name": "Free", "reusable": true, "x": 0, "y": 1500,
       "width": 300, "height": 200, "layout": "none", "children": [
        {"id": "Area", "type": "frame", "name": "Area", "slot": [], "x": 20, "y": 30,
         "width": 200, "height": 100, "layout": "none"}]},
      {"id": "FreeInst", "type": "ref", "ref": "Free", "name": "Free Instance", "x": 400, "y": 1500,
       "descendants": {"Area": {"children": [
         {"id": "Dot", "type": "rectangle", "name": "Dot", "x": 5, "y": 6, "width": 10, "height": 10}]}}},
      {"id": "Board", "type": "frame", "name": "Board", "x": 0, "y": 500, "width": 400, "height": 300,
       "layout": "none", "children": [
        {"id": "Loose", "type": "rectangle", "name": "Loose", "x": 10, "y": 10, "width": 50, "height": 20}]},
      {"id": "Stack", "type": "frame", "name": "Stack", "x": 500, "y": 500, "width": 200,
       "height": "fit_content", "layout": "vertical", "children": [
        {"id": "S1", "type": "rectangle", "name": "S1", "width": 20, "height": 20}]}
    ]}
    """

    /// A fresh copy of the fixture.
    static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    /// A full layout of the document as it stands.
    static func layout(of document: EditableDocument) -> PenLayoutState {
        PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
    }

    /// Applies a plan's operations in order.
    static func apply(_ operations: [EditOperation], to document: EditableDocument) throws {
        for operation in operations {
            try document.apply(operation)
        }
    }

    /// The `descendants` entry an instance stores under a key, as raw properties.
    static func entry(_ key: String, of refID: String, in document: EditableDocument) -> [String: AnyCodable]? {
        guard case let .ref(data)? = document.nodes[refID]?.kind else { return nil }
        return data.descendants?[key]?.properties
    }

    /// The ids of a fill's top-level nodes, as stored.
    static func fillIDs(_ key: String, of refID: String, in document: EditableDocument) -> [String]? {
        guard case let .array(children)? = entry(key, of: refID, in: document)?["children"] else { return nil }
        return children.compactMap { value in
            guard case let .dictionary(node) = value, case let .string(id)? = node["id"] else { return nil }
            return id
        }
    }

    /// The expanded ids under a node of the expanded document, in order, or `nil` when
    /// the expanded document holds no such node.
    static func expandedChildren(of id: String, in document: EditableDocument) -> [String]? {
        func find(_ nodes: [PenNode]) -> PenNode? {
            for node in nodes {
                if node.id == id { return node }
                if let hit = find(node.kind.inlineChildren) { return hit }
            }
            return nil
        }
        return find(document.expandedDocument().0.children).map { $0.kind.inlineChildren.map(\.id) }
    }

    /// The refusal a throwing plan raises, or `nil` when it plans.
    static func refusal(_ body: () throws(EditRefusal) -> some Any) -> EditRefusal? {
        do {
            _ = try body()
            return nil
        } catch {
            return error
        }
    }
}
