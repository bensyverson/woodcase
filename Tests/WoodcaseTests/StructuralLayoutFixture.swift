//
//  StructuralLayoutFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A multi-board document for testing which boards a structural edit lays out again.
///
/// ```
/// Card     reusable: title, body frame (one text)
/// Panel    reusable: title, an instance of Card
/// B1       plain board: title, a list of three rows
/// B2       title, an instance of Card (title overridden)
/// B3       title, an instance of Panel (title overridden)
/// B4       plain board: title, a list of one row, a ref to a missing "Ghost"
/// R5       a top-level instance of Card (title overridden)
/// ```
///
/// `Card` and `Panel` are never laid out on their own:
/// ``EditableDocument/expandedDocument()`` leaves reusable roots out.
@MainActor
struct StructuralLayoutFixture {
    /// The document under test, laid out once and with its dirty tracking cleared.
    let document: EditableDocument

    /// The measurer every layout of ``document`` uses.
    let recorder = RecordingTextMeasurer()

    /// Loads the document and primes its layout cache with a full pass.
    init() throws {
        document = try EditableDocument(from: PenParser.parse(Self.json))
        document.computeLayout(textMeasurer: recorder.measurer)
        document.clearDirtyNodes()
        recorder.reset()
    }

    /// Applies an edit, lays the document out again and checks the result against
    /// ``LayoutOracle``.
    ///
    /// - Parameter operation: The edit.
    /// - Returns: What the layout pass reported — which roots it laid out
    ///   (``PenLayoutChange/affectedRoots``), which containers
    ///   (``PenLayoutStats/containersLaidOut``), and which rects changed.
    @discardableResult
    func applyAndLayOut(
        _ operation: EditOperation,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> PenLayoutChange {
        try document.apply(operation)
        return try layOut(sourceLocation: sourceLocation)
    }

    /// Lays the document out again after edits already applied, and checks the result
    /// against ``LayoutOracle``.
    ///
    /// - Returns: What the layout pass reported.
    @discardableResult
    func layOut(sourceLocation: SourceLocation = #_sourceLocation) throws -> PenLayoutChange {
        recorder.reset()
        let change = document.computeLayout(textMeasurer: recorder.measurer)
        // A measurer of its own, so the oracle's pass stays out of the record.
        let full = LayoutOracle.fullLayout(of: document, textMeasurer: RecordingTextMeasurer().measurer)
        #expect(document.layoutRects == full, "incremental layout differs from full layout", sourceLocation: sourceLocation)
        return change
    }

    /// A text node with the given id and content.
    static func text(_ id: String, _ content: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(width: .fitContent(fallback: nil), content: .literal(content)))
        )
    }

    /// The document.
    static let json: String = """
    {
      "version": "2.17",
      "children": [
        { "id": "Card", "type": "frame", "reusable": true, "x": 2000, "y": 0,
          "layout": "vertical", "gap": 4, "width": 200, "height": "fit_content",
          "children": [
            { "id": "cardTitle", "type": "text", "content": "Card title" },
            { "id": "cardBody", "type": "frame", "layout": "vertical",
              "width": "fill_container", "height": "fit_content",
              "children": [ { "id": "cardBodyText", "type": "text", "content": "Card body" } ] }
          ] },
        { "id": "Panel", "type": "frame", "reusable": true, "x": 2400, "y": 0,
          "layout": "vertical", "gap": 4, "width": "fit_content", "height": "fit_content",
          "children": [
            { "id": "panelTitle", "type": "text", "content": "Panel title" },
            { "id": "panelCard", "type": "ref", "ref": "Card" }
          ] },
        { "id": "B1", "type": "frame", "x": 0, "y": 0,
          "layout": "vertical", "gap": 8, "width": 300, "height": "fit_content",
          "children": [
            { "id": "b1Title", "type": "text", "content": "B1 title" },
            { "id": "b1List", "type": "frame", "layout": "vertical", "gap": 2,
              "width": "fill_container", "height": "fit_content",
              "children": [
                { "id": "b1Row1", "type": "text", "content": "B1 row one" },
                { "id": "b1Row2", "type": "text", "content": "B1 row two" },
                { "id": "b1Row3", "type": "text", "content": "B1 row three" }
              ] }
          ] },
        { "id": "B2", "type": "frame", "x": 400, "y": 0,
          "layout": "vertical", "gap": 8, "width": "fit_content", "height": "fit_content",
          "children": [
            { "id": "b2Title", "type": "text", "content": "B2 title" },
            { "id": "b2Card", "type": "ref", "ref": "Card",
              "descendants": { "cardTitle": { "content": "B2 card title" } } }
          ] },
        { "id": "B3", "type": "frame", "x": 800, "y": 0,
          "layout": "vertical", "gap": 8, "width": "fit_content", "height": "fit_content",
          "children": [
            { "id": "b3Title", "type": "text", "content": "B3 title" },
            { "id": "b3Panel", "type": "ref", "ref": "Panel",
              "descendants": { "panelTitle": { "content": "B3 panel title" } } }
          ] },
        { "id": "B4", "type": "frame", "x": 1200, "y": 0,
          "layout": "vertical", "gap": 8, "width": 300, "height": "fit_content",
          "children": [
            { "id": "b4Title", "type": "text", "content": "B4 title" },
            { "id": "b4List", "type": "frame", "layout": "vertical",
              "width": "fill_container", "height": "fit_content",
              "children": [ { "id": "b4Row1", "type": "text", "content": "B4 row one" } ] },
            { "id": "b4Ghost", "type": "ref", "ref": "Ghost" }
          ] },
        { "id": "R5", "type": "ref", "ref": "Card", "x": 1600, "y": 0,
          "descendants": { "cardTitle": { "content": "R5 title" } } }
      ]
    }
    """
}
