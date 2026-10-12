//
//  ComputeLayoutChangeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditableDocument/computeLayout(textMeasurer:)`` lays out through the one
/// ``PenLayoutState`` its layout cache holds, and reports what changed as a
/// ``PenLayoutChange`` (leaf `df281f`, design decision 3).
@MainActor
struct ComputeLayoutChangeTests {
    private let measurer = RecordingTextMeasurer().measurer

    private func makeDocument() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(PenLayoutStateTests.json))
    }

    @Test("The first pass reports every rect as new")
    func firstPassReportsEverything() throws {
        let document = try makeDocument()
        let change = document.computeLayout(textMeasurer: measurer)

        #expect(change.rects == document.layoutRects)
        #expect(change.resized == Set(document.layoutRects.keys))
        #expect(change.affectedRoots == ["B", "Other"])
        #expect(document.layoutRects == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("A later pass reports exactly the rects an edit changed")
    func laterPassReportsTheEdit() throws {
        let document = try makeDocument()
        document.computeLayout(textMeasurer: measurer)
        document.clearDirtyNodes()
        let before = document.layoutRects

        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "r3", properties: ["kind.height": .int(50)])))
        let change = document.computeLayout(textMeasurer: measurer)

        #expect(change.resized == ["r3", "r3.cell", "list", "B"])
        #expect(change.moved == ["r4", "r5", "footer"])
        #expect(change.affectedRoots == ["B"])
        #expect(Set(change.stats.containersLaidOut) == ["r3", "r3.cell", "list", "B"])
        #expect(change.applied(to: before) == document.layoutRects)
        #expect(document.layoutRects == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))
    }

    @Test("A pass with nothing dirty changes nothing")
    func cleanPassIsEmpty() throws {
        let document = try makeDocument()
        document.computeLayout(textMeasurer: measurer)
        document.clearDirtyNodes()

        let change = document.computeLayout(textMeasurer: measurer)
        #expect(change.isEmpty)
        #expect(change.stats.containersLaidOut.isEmpty)
    }

    @Test("A host's incremental layout and computeLayout share the cache's state")
    func hostPathSharesTheState() throws {
        let document = try makeDocument()
        document.computeLayout(textMeasurer: measurer)
        document.clearDirtyNodes()

        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "r3", properties: ["kind.height": .int(50)])))
        let resolved = PenVariableResolver.resolve(document.expandedDocument().0)
        let rects = document.layoutIncremental(document: resolved, textMeasurer: measurer)
        #expect(rects == document.layoutRects)
        #expect(rects == LayoutOracle.fullLayout(of: document, textMeasurer: measurer))

        // The host pass committed the edit to the state: nothing is left to lay out.
        document.clearDirtyNodes()
        #expect(document.computeLayout(textMeasurer: measurer).isEmpty)
    }
}
