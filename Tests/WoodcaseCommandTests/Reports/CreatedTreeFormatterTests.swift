//
//  CreatedTreeFormatterTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Every mutating verb answers with the name → id map of what it made. This is that
/// answer, in both shapes.
@Suite("Created-tree output")
struct CreatedTreeFormatterTests {
    private let card = CreatedNode(
        id: "ALu8G",
        name: "Card",
        children: [CreatedNode(id: "x9Kqp", name: "Title")]
    )

    // MARK: - Text

    @Test("A created subtree is a name → id outline, two spaces per level")
    func nestedOutline() {
        #expect(CreatedTreeFormatter.text([card]) == "Card  ALu8G\n  Title  x9Kqp")
    }

    @Test("Nothing created prints nothing")
    func emptyIsEmpty() {
        #expect(CreatedTreeFormatter.text([]).isEmpty)
    }

    @Test("Several roots print in order")
    func severalRoots() {
        let second = CreatedNode(id: "Zz1", name: "Note")
        #expect(CreatedTreeFormatter.text([card, second]) == """
        Card  ALu8G
          Title  x9Kqp
        Note  Zz1
        """)
    }

    @Test("A node with no name shows the id marker that addresses it")
    func unnamedNodeShowsItsMarker() {
        let unnamed = CreatedNode(id: "Q7zz", children: [])
        #expect(CreatedTreeFormatter.text([unnamed]) == "#Q7zz  Q7zz")
    }

    @Test("The outline never ends in a newline or a space")
    func noTrailingWhitespace() {
        let text = CreatedTreeFormatter.text([card])
        #expect(!text.hasSuffix("\n"))
        #expect(text.split(separator: "\n").allSatisfy { !$0.hasSuffix(" ") })
    }

    @Test("The same tree renders the same bytes every time")
    func deterministic() throws {
        #expect(CreatedTreeFormatter.text([card]) == CreatedTreeFormatter.text([card]))
        #expect(
            try CreatedTreeFormatter.json([card], revision: "r1")
                == CreatedTreeFormatter.json([card], revision: "r1")
        )
    }

    // MARK: - JSON

    @Test("The JSON form carries what was created and the revision it left behind")
    func jsonShape() throws {
        let json = try CreatedTreeFormatter.json([card], revision: "rev-9")
        let report = try JSONDecoder().decode(
            CreatedTreeReport.self, from: Data(json.utf8)
        )
        #expect(report.revision == "rev-9")
        #expect(report.created == [card])
    }

    @Test("The JSON form is pretty-printed with sorted keys")
    func jsonIsReadable() throws {
        let json = try CreatedTreeFormatter.json([card], revision: "rev-9")
        #expect(json.contains("\n"))
        let createdIndex = try #require(json.range(of: "\"created\""))
        let revisionIndex = try #require(json.range(of: "\"revision\""))
        #expect(createdIndex.lowerBound < revisionIndex.lowerBound)
    }

    @Test("A verb that created nothing still reports the revision")
    func jsonWithNothingCreated() throws {
        let json = try CreatedTreeFormatter.json([], revision: "rev-9")
        let report = try JSONDecoder().decode(
            CreatedTreeReport.self, from: Data(json.utf8)
        )
        #expect(report.created.isEmpty)
        #expect(report.revision == "rev-9")
    }
}
