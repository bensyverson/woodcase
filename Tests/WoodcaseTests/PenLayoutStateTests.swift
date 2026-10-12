//
//  PenLayoutStateTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Node-granular layout: ``PenLayoutState`` lays out what an edit names and only that,
/// and its result equals a full layout.
@MainActor
struct PenLayoutStateTests {
    /// A board holding a five-row list, each row a title and a cell that fills it, and a
    /// second root that no edit here touches.
    nonisolated static let json: String = """
    {
      "version": "2.17",
      "children": [
        { "id": "B", "type": "frame", "x": 0, "y": 0, "layout": "vertical", "gap": 4,
          "padding": 8, "width": 400, "height": "fit_content",
          "children": [
            { "id": "title", "type": "text", "content": "A board" },
            { "id": "list", "type": "frame", "layout": "vertical", "gap": 2,
              "width": "fill_container", "height": "fit_content",
              "children": [
                \((1 ... 5).map(Self.row).joined(separator: ",\n"))
              ] },
            { "id": "footer", "type": "group", "children": [
              { "id": "f1", "type": "rectangle", "x": 0, "y": 0, "width": 20, "height": 10 },
              { "id": "f2", "type": "rectangle", "x": 30, "y": 5, "width": 20, "height": 10 }
            ] }
          ] },
        { "id": "Other", "type": "frame", "x": 600, "y": 0, "layout": "vertical",
          "children": [ { "id": "otherText", "type": "text", "content": "Elsewhere" } ] }
      ]
    }
    """

    /// One row: a horizontal frame 30 points tall with a title and a filling cell.
    nonisolated static func row(_ number: Int) -> String {
        """
        { "id": "r\(number)", "type": "frame", "layout": "horizontal", "gap": 4,
          "width": "fill_container", "height": 30,
          "children": [
            { "id": "r\(number).t", "type": "text", "content": "Row \(number)" },
            { "id": "r\(number).cell", "type": "frame", "layout": "vertical",
              "width": "fill_container", "height": "fill_container",
              "children": [ { "id": "r\(number).c", "type": "text", "content": "Cell of row \(number)" } ] }
          ] }
        """
    }

    private let measurer = RecordingTextMeasurer().measurer

    private func makeDocument() throws -> EditableDocument {
        let document = try EditableDocument(from: PenParser.parse(Self.json))
        document.primeLayoutCache(with: [:])
        return document
    }

    private func resolved(_ document: EditableDocument) -> PenDocument {
        PenVariableResolver.resolve(document.expandedDocument().0)
    }

    // MARK: - Full and incremental

    @Test("A new state holds exactly a full layout")
    func initialLayout() throws {
        let document = try makeDocument()
        let state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        #expect(state.rects == PenLayoutEngine.layout(resolved(document), textMeasurer: measurer))
    }

    @Test("After one row is resized, only its ancestors and the cell whose space changed are laid out")
    func resizeLaysOutAncestorsAndFillDescendants() throws {
        let document = try makeDocument()
        var state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        document.clearDirtyNodes()
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "r3", properties: ["kind.height": .int(50)])))
        let change = state.update(to: resolved(document), invalidation: document.layoutInvalidation)

        #expect(Set(change.stats.containersLaidOut) == ["r3", "r3.cell", "list", "B"])
        #expect(state.rects == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("A change lists exactly the ids whose rect differs, and how each moved")
    func changeListsExactlyTheDifferences() throws {
        let document = try makeDocument()
        var state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let before = state.rects
        document.clearDirtyNodes()
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "r3", properties: ["kind.height": .int(50)])))
        let change = state.update(to: resolved(document), invalidation: document.layoutInvalidation)

        let differing = Set(state.rects.keys).union(before.keys).filter { state.rects[$0] != before[$0] }
        #expect(Set(change.rects.keys).union(change.removed) == differing)
        #expect(change.resized == ["r3", "r3.cell", "list", "B"])
        #expect(change.moved == ["r4", "r5", "footer"])
        #expect(change.topmost == ["B"])
        #expect(change.affectedRoots == ["B"])
        #expect(change.applied(to: before) == state.rects)
    }

    @Test("A structural edit named by its parent's spine alone updates node by node", arguments: ["move", "delete", "insert"])
    func spineOnlyStructuralUpdate(edit: String) throws {
        let document = try makeDocument()
        var state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let before = state.rects
        switch edit {
        case "move":
            try document.apply(.moveNode(EditOperation.MoveNode(nodeID: "r5", newParentID: "list", index: 0)))
        case "delete":
            try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "r2")))
        default:
            let row = try PenParser.parse("{ \"version\": \"2.17\", \"children\": [\(Self.row(9))] }").children[0]
            try document.apply(.insertNode(EditOperation.InsertNode(node: row, parentID: "list", index: 2)))
        }
        // What leaf df281f's narrowed structural scope would record: the parent's spine.
        let change = state.update(to: resolved(document), invalidation: PenLayoutInvalidation(nodes: ["list", "B"]))

        #expect(state.rects == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
        #expect(change.applied(to: before) == state.rects)
        #expect(Set(change.stats.containersLaidOut).subtracting(["r9", "r9.cell"]) == ["list", "B"])
    }

    // MARK: - Hypothetical

    @Test("A hypothetical move equals the rects after committing that move, and leaves the document alone")
    func hypotheticalMoveEqualsCommittedMove() throws {
        let document = try makeDocument()
        let state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let revision = document.documentRevision
        let change = state.hypothetical([.move("r4", toIndex: 1)])
        #expect(document.documentRevision == revision)
        #expect(change.moved == ["r2", "r3", "r4"])

        try document.apply(.moveNode(EditOperation.MoveNode(nodeID: "r4", newParentID: "list", index: 1)))
        #expect(change.applied(to: state.rects) == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("A hypothetical move lays out only the list and its ancestors")
    func hypotheticalMoveIsNarrow() throws {
        let document = try makeDocument()
        let state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let change = state.hypothetical([.move("r1", toIndex: 4)])
        #expect(Set(change.stats.containersLaidOut) == ["list", "B"])
        #expect(change.stats.leavesSized == 0)
    }

    @Test("A hypothetical remove closes the gap, as deleting the row would")
    func hypotheticalRemove() throws {
        let document = try makeDocument()
        let state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let change = state.hypothetical([.remove("r2")])
        #expect(change.removed == ["r2", "r2.t", "r2.cell", "r2.c"])

        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "r2")))
        #expect(change.applied(to: state.rects) == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("A hypothetical size equals the rects of that node at that fixed size")
    func hypotheticalSize() throws {
        let document = try makeDocument()
        let state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let change = state.hypothetical([.size("r3", width: 250, height: 44)])

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "r3", properties: ["kind.width": .int(250), "kind.height": .int(44)]
        )))
        #expect(change.applied(to: state.rects) == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("A hypothetical sizing equals the rects after setting that sizing")
    func hypotheticalSizing() throws {
        let document = try makeDocument()
        let state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let change = state.hypothetical([.sizing("list", width: .fixed(300), height: nil)])

        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "list", properties: ["kind.width": .int(300)])))
        #expect(change.applied(to: state.rects) == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("Edits on ids the state does not hold are passed over; the rest still apply")
    func unknownIDs() throws {
        let document = try makeDocument()
        let state = PenLayoutState(document: resolved(document), textMeasurer: measurer)
        let change = state.hypothetical([
            .remove("gone"), .move("r4", toIndex: 1), .size("none", width: 1, height: 1), .move("nope", toIndex: 0),
        ])

        try document.apply(.moveNode(EditOperation.MoveNode(nodeID: "r4", newParentID: "list", index: 1)))
        #expect(change.applied(to: state.rects) == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
        #expect(change.removed.isEmpty)
    }
}
