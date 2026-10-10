//
//  TreeFormatterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct TreeFormatterTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func document(_ fixture: String) throws -> EditableDocument {
        let base = (fixture as NSString).deletingPathExtension
        let ext = (fixture as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(fixture)
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    // MARK: - Text

    @Test("The text form is byte-stable, name first, and marks both clip states on the name")
    func textIsByteStable() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        let expected = """
        name                   type       rect           id
        Card                   frame      0,0 200×100    Card1
          fits                 rectangle  10,10 50×50    Fit01
          overflows ⚠ partial  rectangle  160,20 80×40   Ovr01
          #Out01 ⚠ clipped     rectangle  260,120 20×20  Out01
        """
        #expect(TreeFormatter.text(rows) == expected)
    }

    @Test("Depth is the line's leading indentation, whatever the type's width")
    func depthIsLeadingIndentation() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        let lines = TreeFormatter.text(rows).split(separator: "\n").dropFirst()
        let indents = lines.map { $0.prefix { $0 == " " }.count }
        #expect(indents == rows.map { $0.depth * 2 })
    }

    @Test("Property columns sit between the rect and the id, so the id is always last")
    func textWithPropertyColumns() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"), properties: ["kind.width"])
        let expected = """
        name                   type       rect           kind.width  id
        Card                   frame      0,0 200×100    200         Card1
          fits                 rectangle  10,10 50×50    50          Fit01
          overflows ⚠ partial  rectangle  160,20 80×40   80          Ovr01
          #Out01 ⚠ clipped     rectangle  260,120 20×20  20          Out01
        """
        #expect(TreeFormatter.text(rows, properties: ["kind.width"]) == expected)
    }

    @Test("Every listing opens with a header row, and an absolute one says so")
    func headerRowIsAlwaysPrinted() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        let relative = TreeFormatter.text(rows).split(separator: "\n")[0]
        let absolute = TreeFormatter.text(rows, absolute: true).split(separator: "\n")[0]
        #expect(relative.split(separator: " ") == ["name", "type", "rect", "id"])
        #expect(absolute.split(separator: " ") == ["name", "type", "absRect", "id"])
    }

    @Test("Children left out of the listing are counted on the row that hides them")
    func hiddenChildrenAreCounted() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"), depth: 0)
        #expect(TreeFormatter.text(rows) == """
        name     type   rect         id
        Card +3  frame  0,0 200×100  Card1
        """)
    }

    @Test("A collapsed instance and a component definition are both marked on the name")
    func instanceAndComponentMarkers() throws {
        let rows = try TreeView.rows(of: document("addressing.pen"), root: "Dashboard/Body")
        let text = TreeFormatter.text(rows)
        #expect(text.contains("ref"))
        #expect(text.contains("Nav +2"))

        let component = try TreeView.rows(of: document("addressing.pen"), root: "Button", depth: 0)
        let row = try #require(TreeFormatter.text(component).split(separator: "\n").last)
        #expect(row.hasPrefix("*Button"))
        #expect(row.contains("  frame  "))
    }

    @Test("A selection prints flush, with no hidden-children count, since its rows are not a walk")
    func selectionIsFlush() throws {
        let all = try TreeView.rows(of: document("tree-overflow.pen"), depth: 0)
            + TreeView.rows(of: document("tree-overflow.pen")).filter { $0.id == "Out01" }
        #expect(TreeFormatter.text(all, listing: .selection) == """
        name              type       rect           id
        Card              frame      0,0 200×100    Card1
        #Out01 ⚠ clipped  rectangle  260,120 20×20  Out01
        """)
    }

    @Test("The text form never has a trailing space on a line")
    func noTrailingWhitespace() throws {
        let rows = try TreeView.rows(of: document("addressing.pen"), expandInstances: true)
        for line in TreeFormatter.text(rows).split(separator: "\n", omittingEmptySubsequences: false) {
            #expect(!line.hasSuffix(" "), "trailing space on: \(line)")
        }
    }

    // MARK: - JSON

    @Test("The JSON form carries the document revision and decodes back to the rows")
    func jsonRoundTrips() throws {
        let doc = try document("tree-overflow.pen")
        let rows = try TreeView.rows(of: doc, properties: ["kind.width"])
        let json = try TreeFormatter.json(rows, revision: doc.documentRevision)

        let report = try JSONDecoder().decode(TreeReport.self, from: Data(json.utf8))
        #expect(report.revision == doc.documentRevision)
        #expect(report.rows == rows)
    }

    @Test("The JSON form is pretty-printed with sorted keys")
    func jsonIsPrettySorted() throws {
        let doc = try document("tree-overflow.pen")
        let json = try TreeFormatter.json(TreeView.rows(of: doc), revision: doc.documentRevision)

        #expect(json.contains("\n"))
        let addressIndex = try #require(json.range(of: "\"address\"")).lowerBound
        let clipIndex = try #require(json.range(of: "\"clip\"")).lowerBound
        let depthIndex = try #require(json.range(of: "\"depth\"")).lowerBound
        #expect(addressIndex < clipIndex)
        #expect(clipIndex < depthIndex)
        #expect(json.range(of: "\"revision\"") != nil)
    }

    @Test("overflowAxes encodes in a canonical order, never Set's hash order")
    func overflowAxesJSONIsDeterministic() throws {
        let doc = try document("tree-overflow.pen")
        // Out01 overflows both axes; TreeView.rows(of:) recomputes the row — and its
        // overflow axes — fresh on every call, so 30 independent reads stand in for
        // "many fresh Sets" without needing 30 separate process launches.
        for _ in 0 ..< 30 {
            let rows = try TreeView.rows(of: doc)
            let json = try TreeFormatter.json(rows, revision: doc.documentRevision)
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            )
            let reportRows = try #require(object["rows"] as? [[String: Any]])
            let out01 = try #require(reportRows.first { $0["id"] as? String == "Out01" })
            let axes = try #require(out01["overflowAxes"] as? [String])
            #expect(axes == ["horizontal", "vertical"])
        }
    }
}
