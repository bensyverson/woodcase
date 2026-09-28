//
//  PenRefExpanderSlotKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How ``PenRefExpander`` applies an override keyed to a node written into a nested
/// instance's slot, and what it does when two keys name the same node.
///
/// Pen applies only one override per node — the key written *last* in the file, whole,
/// never merged (`project/2026-09-26-slot-override-keys.md`). Woodcase's model does not
/// keep the order the keys were written in, so it takes the key that sorts last: the
/// order Woodcase itself writes them in, which makes the two agree on every file
/// Woodcase has saved.
struct PenRefExpanderSlotKeyTests {
    /// `Card` places a `Slot` instance and writes a `Chip` rectangle into its hole.
    private static func document(descendants: String) throws -> PenDocument {
        let json = """
        {"version": "2.17", "children": [
          {"id": "Slot", "type": "frame", "reusable": true, "width": 100, "height": 40, "children": [
            {"id": "Hole", "type": "frame", "width": 60, "height": 30, "children": []}]},
          {"id": "Card", "type": "frame", "reusable": true, "width": 100, "height": 40, "children": [
            {"id": "Place", "type": "ref", "ref": "Slot", "descendants": {"Hole": {"children": [
              {"id": "Chip", "type": "rectangle", "width": 20, "height": 20, "fill": "#FF0000"},
              {"id": "Zone", "type": "rectangle", "width": 20, "height": 20, "fill": "#FF0000"}]}}}]},
          {"id": "Inst", "type": "ref", "ref": "Card", "descendants": \(descendants)}
        ]}
        """
        return try PenParser.parse(Data(json.utf8))
    }

    /// The expanded rectangle with this id, anywhere in the document.
    private static func rectangle(_ id: String, in document: PenDocument) -> PenNode.RectangleData? {
        func find(_ nodes: [PenNode]) -> PenNode.RectangleData? {
            for node in nodes {
                if node.id == id, case let .rectangle(data) = node.kind { return data }
                if let found = find(node.kind.inlineChildren) { return found }
            }
            return nil
        }
        return find(document.children)
    }

    private static func fill(_ id: String, in document: PenDocument) -> String? {
        guard case let .shorthand(color)? = rectangle(id, in: document)?.fills?.all.first else { return nil }
        return color
    }

    @Test("A bare key reaches the node the component wrote into a nested slot")
    func bareKeyReachesSlotContent() throws {
        let expanded = try PenRefExpander.expand(Self.document(descendants: ##"{"Chip": {"fill": "#0000FF"}}"##))

        #expect(Self.fill("Inst/Place/Chip", in: expanded) == "#0000FF")
        #expect(Self.fill("Inst/Place/Zone", in: expanded) == "#FF0000")
    }

    @Test("Of two keys naming one node, the one that sorts last applies, whole")
    func lastSortedKeyWinsWhole() throws {
        let pathLast = try PenRefExpander.expand(Self.document(
            descendants: ##"{"Chip": {"height": 10}, "Place/Chip": {"fill": "#00FF00"}}"##
        ))
        #expect(Self.fill("Inst/Place/Chip", in: pathLast) == "#00FF00")
        #expect(Self.rectangle("Inst/Place/Chip", in: pathLast)?.height == .fixed(20))

        let bareLast = try PenRefExpander.expand(Self.document(
            descendants: ##"{"Zone": {"fill": "#0000FF"}, "Place/Zone": {"height": 10}}"##
        ))
        #expect(Self.fill("Inst/Place/Zone", in: bareLast) == "#0000FF")
        #expect(Self.rectangle("Inst/Place/Zone", in: bareLast)?.height == .fixed(20))
    }
}
