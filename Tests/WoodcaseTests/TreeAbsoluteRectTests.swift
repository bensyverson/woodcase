//
//  TreeAbsoluteRectTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Document-space rects on a tree read.
///
/// ``TreeRow/rect`` is the layout engine's own convention — an offset inside the
/// node's own parent — and three separate agents re-derived the absolute coordinate
/// by walking parents themselves before ``TreeRow/absRect`` existed. The rule this
/// suite pins is that they never have to again, and that the number they get is the
/// one `shot --outline` draws with rather than a second arithmetic of its own.
@MainActor
@Suite("Absolute rects on a tree read")
struct TreeAbsoluteRectTests {
    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    private func document(_ fixture: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: fixtureURL(fixture)))
    }

    /// The rects `shot` composes for a top-level node's subtree: the settle it runs,
    /// then the one absolute walk it and the viewer share.
    private func shotRects(of document: EditableDocument, rootID: String) -> [String: PenRect] {
        let expanded = PenRefExpander.expand(document.materialize(), for: .canvas)
        let resolved = PenVariableResolver.resolve(expanded, theme: [:])
        return PenLayoutEngine.absoluteRects(
            under: rootID, in: resolved, layoutRects: PenLayoutEngine.layout(resolved)
        )
    }

    @Test("Every row's absRect is the rect shot composes for the same node")
    func absRectMatchesShotsOwnWalk() throws {
        let doc = try document("layout-deep-nesting.pen")
        let rows = try TreeView.rows(of: doc)
        let expected = shotRects(of: doc, rootID: "Ms0rE")

        #expect(!rows.isEmpty)
        for row in rows {
            #expect(row.absRect == expected[row.id], "absRect mismatch for \(row.id)")
        }
    }

    @Test("A nested row carries both frames: parent-relative and document-space")
    func nestedRowCarriesBothFrames() throws {
        let rows = try TreeView.rows(of: document("layout-deep-nesting.pen"))
        let leaf = try #require(rows.first { $0.id == "gaLFu" })

        // Ms0rE(0,0) → S4auN(10,10) → o3V8H(193,8) → D48Fa(6,6) → gaLFu(0,0).
        #expect(leaf.rect == PenRect(x: 0, y: 0, width: 30, height: 20))
        #expect(leaf.absRect == PenRect(x: 209, y: 24, width: 30, height: 20))
    }

    @Test("A top-level row's two rects are the same, because its parent is the canvas")
    func rootRowsAgreeWithThemselves() throws {
        let rows = try TreeView.rows(of: document("layout-deep-nesting.pen"))
        let root = try #require(rows.first { $0.id == "Ms0rE" })
        #expect(root.rect == root.absRect)
    }

    @Test("A row inside an expanded component instance carries an absRect too")
    func expandedInstanceRowsCarryAbsRects() throws {
        let doc = try document("addressing-nested-instance.pen")
        let rows = try TreeView.rows(of: doc, expandInstances: true)

        let nested = rows.filter { $0.depth > 0 && $0.rect != nil }
        #expect(!nested.isEmpty)
        for row in nested {
            #expect(row.absRect != nil, "no absRect for \(row.id)")
        }
    }

    // MARK: - The text form

    @Test("The text form prints the parent-relative rect unless it is asked otherwise")
    func textFormDefaultsToParentRelative() throws {
        let rows = try TreeView.rows(of: document("layout-deep-nesting.pen"))

        let relative = TreeFormatter.text(rows)
        let absolute = TreeFormatter.text(rows, absolute: true)

        #expect(relative.contains("0,0 30×20"))
        #expect(absolute.contains("209,24 30×20"))
        #expect(!absolute.contains("209,24 30×20\n209,24"))
    }

    @Test("The column header names the coordinate system the column is in")
    func headerNamesTheCoordinateSystem() throws {
        let rows = try TreeView.rows(of: document("layout-deep-nesting.pen"))
        let properties = ["kind.fill"]

        #expect(TreeFormatter.text(rows, properties: properties).contains("rect"))
        let absolute = TreeFormatter.text(rows, properties: properties, absolute: true)
        #expect(absolute.components(separatedBy: "\n")[0].contains("absRect"))
    }
}
