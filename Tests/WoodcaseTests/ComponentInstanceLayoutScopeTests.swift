//
//  ComponentInstanceLayoutScopeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An edit inside a component names the placed instances that draw it — their refs, in
/// ``PenLayoutInvalidation/nodes`` — rather than the boards holding them, so a layout
/// pass lays out each instance and its spine, and the rest of each board answers from
/// memory (Penumbra's ask, 2026-10-12: a definition edit laid out every drawing board
/// whole, 57–68 ms on a 160-instance board).
@MainActor
struct ComponentInstanceLayoutScopeTests {
    /// `Card` (reusable), and a board holding a list and an instance of it, and a second
    /// board holding an instance of `Panel`, which nests `Card`.
    static let json = """
    {
      "version": "2.17",
      "children": [
        { "id": "Card", "type": "frame", "reusable": true, "x": 2000, "y": 0,
          "layout": "vertical", "width": 200, "height": "fit_content",
          "children": [ { "id": "cardText", "type": "text", "content": "Card text" } ] },
        { "id": "Panel", "type": "frame", "reusable": true, "x": 2400, "y": 0,
          "layout": "vertical", "width": "fit_content", "height": "fit_content",
          "children": [ { "id": "panelCard", "type": "ref", "ref": "Card" } ] },
        { "id": "Board", "type": "frame", "x": 0, "y": 0, "layout": "vertical", "gap": 8,
          "width": 400, "height": "fit_content",
          "children": [
            { "id": "list", "type": "frame", "layout": "vertical", "width": "fill_container",
              "height": "fit_content",
              "children": [
                { "id": "row1", "type": "text", "content": "Row one" },
                { "id": "row2", "type": "text", "content": "Row two" }
              ] },
            { "id": "inst", "type": "ref", "ref": "Card" }
          ] },
        { "id": "Other", "type": "frame", "x": 600, "y": 0, "layout": "vertical",
          "children": [
            { "id": "otherList", "type": "frame", "layout": "vertical",
              "children": [ { "id": "otherRow", "type": "text", "content": "Other row" } ] },
            { "id": "otherPanel", "type": "ref", "ref": "Panel" }
          ] }
      ]
    }
    """

    private let measurer = RecordingTextMeasurer().measurer

    private func makeDocument() throws -> EditableDocument {
        let document = try EditableDocument(from: PenParser.parse(Self.json))
        document.computeLayout(textMeasurer: measurer)
        document.clearDirtyNodes()
        return document
    }

    @Test("A property edit inside a component names its placed instances, not their boards")
    func propertyEditNamesInstances() throws {
        let document = try makeDocument()
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "cardText", properties: ["kind.content": .string("A card text long enough to wrap inside the card")]
        )))
        let invalidation = document.layoutInvalidation
        #expect(invalidation.roots.isEmpty)
        // `panelCard` too: a canvas lays the `Panel` definition out like a board.
        #expect(invalidation.nodes.isSuperset(of: ["inst", "otherPanel", "panelCard", "Panel"]))

        let change = document.computeLayout(textMeasurer: measurer)
        let laidOut = Set(change.stats.containersLaidOut)
        #expect(change.affectedRoots == ["Board", "Other"])
        #expect(!laidOut.contains("list"))
        #expect(!laidOut.contains("otherList"))
        #expect(laidOut.isSuperset(of: ["Board", "inst/Card", "Other"]))
        #expect(document.layoutRects == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("A structural edit inside a component names its placed instances, not their boards")
    func structuralEditNamesInstances() throws {
        let document = try makeDocument()
        try document.apply(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("cardMore", "More card text"), parentID: "Card"
        )))
        #expect(document.layoutInvalidation.roots.isEmpty)
        #expect(document.dirtyLayoutNodeIDs.isSuperset(of: ["inst", "otherPanel"]))

        let change = document.computeLayout(textMeasurer: measurer)
        let laidOut = Set(change.stats.containersLaidOut)
        #expect(change.affectedRoots == ["Board", "Other"])
        #expect(!laidOut.contains("list"))
        #expect(!laidOut.contains("otherList"))
        #expect(document.layoutRects == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }
}
