//
//  PenRefExpanderPenKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Two `descendants` keys whose fate Pen decides and ``PenRefExpander`` must match.
///
/// Measured with the `pen` CLI (0.3.9) on 2026-09-26 — see
/// `project/2026-09-26-slot-override-keys.md`, *Follow-up*:
///
/// - `Ins/Nested`, a path naming an instance of a nested component's own tree, applies
///   to that instance: Pen draws its fill and its width.
/// - A key naming a node the instance wrote into a slot itself — bare or by path —
///   is dropped: Pen re-saves the file without it and draws the node as written.
struct PenRefExpanderPenKeyTests {
    /// `Cmp` places `Mid`, an instance of `Bar`; `Bar` places `Dot`, an instance of the
    /// red `Red` frame. `Slt` has an empty `Hole` frame, and `Box` places `Inn`, an
    /// instance of it.
    private static func document(instance: String) throws -> PenDocument {
        let json = """
        {"version": "2.17", "children": [
          {"id": "Red", "type": "frame", "reusable": true, "width": 20, "height": 20, "fill": "#FF0000"},
          {"id": "Bar", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Dot", "type": "ref", "ref": "Red", "x": 5, "y": 5}]},
          {"id": "Cmp", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Mid", "type": "ref", "ref": "Bar"}]},
          {"id": "Slt", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Hole", "type": "frame", "width": 150, "height": 30, "children": []}]},
          {"id": "Box", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Inn", "type": "ref", "ref": "Slt"}]},
          \(instance)
        ]}
        """
        return try PenParser.parse(Data(json.utf8))
    }

    /// The expanded node with this id, searched without recursion.
    private static func node(_ id: String, in document: PenDocument) -> PenNode? {
        var pending = document.children
        while let next = pending.popLast() {
            if next.id == id { return next }
            pending.append(contentsOf: next.kind.inlineChildren)
        }
        return nil
    }

    /// A node's solid fill, as a shorthand color.
    private static func fill(of node: PenNode?) -> String? {
        let fills: PenFills? = switch node?.kind {
        case let .frame(data)?: data.fills
        case let .rectangle(data)?: data.fills
        default: nil
        }
        guard case let .shorthand(color)? = fills?.all.first else { return nil }
        return color
    }

    @Test("A path naming a nested component's instance patches that instance")
    func pathToNestedInstanceApplies() throws {
        let expanded = try PenRefExpander.expand(Self.document(instance: ##"""
        {"id": "Use", "type": "ref", "ref": "Cmp", "descendants": {"Mid/Dot": {"fill": "#00FF00", "width": 60}}}
        """##))

        let dot = Self.node("Use/Mid/Dot/Red", in: expanded)
        #expect(Self.fill(of: dot) == "#00FF00")
        guard case let .frame(data)? = dot?.kind else {
            Issue.record("expected the nested instance's root frame")
            return
        }
        #expect(data.width == .fixed(60))
    }

    @Test("A bare key naming a node the instance wrote into its own slot is dropped")
    func bareKeyOnOwnSlotContentIsDropped() throws {
        let expanded = try PenRefExpander.expand(Self.document(instance: ##"""
        {"id": "Use", "type": "ref", "ref": "Slt", "descendants": {
          "Hole": {"children": [{"id": "NewY", "type": "rectangle", "width": 20, "height": 20, "fill": "#FF0000"}]},
          "NewY": {"fill": "#0000FF"}}}
        """##))

        #expect(Self.fill(of: Self.node("Use/NewY", in: expanded)) == "#FF0000")
    }

    @Test("A key naming a node the instance wrote into a nested instance's slot is dropped")
    func pathKeyOnOwnNestedSlotContentIsDropped() throws {
        let expanded = try PenRefExpander.expand(Self.document(instance: ##"""
        {"id": "Use", "type": "ref", "ref": "Box", "descendants": {
          "Inn/Hole": {"children": [{"id": "NewY", "type": "rectangle", "width": 20, "height": 20, "fill": "#FF0000"}]},
          "Inn/NewY": {"fill": "#0000FF"}, "NewY": {"fill": "#0000FF"}}}
        """##))

        #expect(Self.fill(of: Self.node("Use/Inn/NewY", in: expanded)) == "#FF0000")
    }

    @Test("Children the instance writes on its own ref node are not reached by its keys")
    func keyOnOwnRootChildrenIsDropped() throws {
        let expanded = try PenRefExpander.expand(Self.document(instance: ##"""
        {"id": "Use", "type": "ref", "ref": "Slt",
         "children": [{"id": "NewY", "type": "rectangle", "width": 20, "height": 20, "fill": "#FF0000"}],
         "descendants": {"NewY": {"fill": "#0000FF"}}}
        """##))

        #expect(Self.fill(of: Self.node("Use/NewY", in: expanded)) == "#FF0000")
    }
}
