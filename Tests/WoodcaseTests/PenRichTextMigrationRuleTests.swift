//
//  PenRichTextMigrationRuleTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
@testable import Woodcase

/// Covers ``PenRichTextMigrationRule`` — the 2.10 → 2.17 rewrite of styled text runs.
struct PenRichTextMigrationRuleTests {
    // MARK: - Helpers

    /// Runs only the rich-text rule over a document tree.
    private func migrate(
        _ document: [String: AnyCodable],
        diagnostics: PenDiagnosticCollector? = nil
    ) -> [String: AnyCodable] {
        PenLegacyMigrator.migrate(
            document, rules: [PenRichTextMigrationRule()], diagnostics: diagnostics
        )
    }

    /// A text node whose `content` is an array of styled runs.
    private func richTextNode(id: String, runs: [[String: AnyCodable]]) -> AnyCodable {
        .dictionary([
            "type": .string("text"),
            "id": .string(id),
            "content": .array(runs.map { AnyCodable.dictionary($0) }),
            "fontSize": .double(16),
        ])
    }

    /// The `content` of the node at `path` — a sequence of `children` indices from the root.
    private func content(of document: [String: AnyCodable], at path: [Int]) -> AnyCodable? {
        var node: AnyCodable = .dictionary(document)
        for index in path {
            guard case let .dictionary(dict) = node,
                  case let .array(children)? = dict["children"],
                  children.indices.contains(index)
            else { return nil }
            node = children[index]
        }
        guard case let .dictionary(dict) = node else { return nil }
        return dict["content"]
    }

    // MARK: - Concatenation

    @Test("Styled runs concatenate into one string, in order, with no separator")
    func runsConcatenateInOrder() {
        let document: [String: AnyCodable] = [
            "version": .string("2.9"),
            "children": .array([richTextNode(id: "rich", runs: [
                ["content": .string("Bold "), "fontWeight": .string("700")],
                ["content": .string("Italic "), "fontStyle": .string("italic")],
                ["content": .string("Colored"), "fill": .string("#FF0000")],
            ])]),
        ]

        let migrated = migrate(document)

        #expect(content(of: migrated, at: [0]) == .string("Bold Italic Colored"))
    }

    @Test("A run with no content string contributes nothing")
    func runWithoutContentIsSkipped() {
        let document: [String: AnyCodable] = [
            "children": .array([richTextNode(id: "rich", runs: [
                ["content": .string("Kept")],
                ["fontWeight": .string("700")],
                ["content": .string(" too")],
            ])]),
        ]

        #expect(content(of: migrate(document), at: [0]) == .string("Kept too"))
    }

    @Test("An empty run array becomes an empty string")
    func emptyRunArrayBecomesEmptyString() {
        let document: [String: AnyCodable] = [
            "children": .array([richTextNode(id: "rich", runs: [])]),
        ]

        #expect(content(of: migrate(document), at: [0]) == .string(""))
    }

    @Test("A single run holding a variable reference stays a variable reference")
    func singleVariableRunStaysAVariable() {
        let document: [String: AnyCodable] = [
            "children": .array([richTextNode(id: "rich", runs: [
                ["content": .string("$headline")],
            ])]),
        ]

        #expect(content(of: migrate(document), at: [0]) == .string("$headline"))
    }

    @Test("A variable run among several keeps its literal text")
    func variableRunAmongOthersIsKeptLiterally() {
        let document: [String: AnyCodable] = [
            "children": .array([richTextNode(id: "rich", runs: [
                ["content": .string("Price: ")],
                ["content": .string("$amount")],
            ])]),
        ]

        #expect(content(of: migrate(document), at: [0]) == .string("Price: $amount"))
    }

    // MARK: - Scope

    @Test("Plain string content is left untouched")
    func plainContentIsUntouched() {
        let document: [String: AnyCodable] = [
            "children": .array([.dictionary([
                "type": .string("text"),
                "id": .string("plain"),
                "content": .string("Hello World"),
            ])]),
        ]

        #expect(content(of: migrate(document), at: [0]) == .string("Hello World"))
    }

    @Test("A variable-reference content string is left untouched")
    func variableContentIsUntouched() {
        let document: [String: AnyCodable] = [
            "children": .array([.dictionary([
                "type": .string("text"),
                "id": .string("var"),
                "content": .string("$headline"),
            ])]),
        ]

        #expect(content(of: migrate(document), at: [0]) == .string("$headline"))
    }

    @Test("A node with no content is left untouched")
    func absentContentIsUntouched() {
        let document: [String: AnyCodable] = [
            "children": .array([.dictionary([
                "type": .string("text"),
                "id": .string("bare"),
                "fontSize": .double(16),
            ])]),
        ]

        #expect(content(of: migrate(document), at: [0]) == nil)
    }

    @Test("Runs nested inside a frame's children are migrated")
    func nestedChildrenAreMigrated() {
        let document: [String: AnyCodable] = [
            "children": .array([.dictionary([
                "type": .string("frame"),
                "id": .string("frame1"),
                "children": .array([
                    .dictionary([
                        "type": .string("frame"),
                        "id": .string("frame2"),
                        "children": .array([richTextNode(id: "deep", runs: [
                            ["content": .string("Deep ")],
                            ["content": .string("text")],
                        ])]),
                    ]),
                ]),
            ])]),
        ]

        #expect(content(of: migrate(document), at: [0, 0, 0]) == .string("Deep text"))
    }

    @Test("Runs inside a ref's descendant overrides are migrated")
    func refDescendantOverridesAreMigrated() {
        let document: [String: AnyCodable] = [
            "children": .array([.dictionary([
                "type": .string("ref"),
                "id": .string("ref1"),
                "ref": .string("card"),
                "descendants": .dictionary([
                    "card/label": .dictionary([
                        "content": .array([
                            .dictionary(["content": .string("Over"), "fontWeight": .string("700")]),
                            .dictionary(["content": .string("ridden")]),
                        ]),
                    ]),
                ]),
            ])]),
        ]

        let migrated = migrate(document)
        guard case let .array(children)? = migrated["children"],
              case let .dictionary(ref) = children[0],
              case let .dictionary(descendants)? = ref["descendants"],
              case let .dictionary(override)? = descendants["card/label"]
        else {
            Issue.record("Expected the ref's descendant override to survive migration")
            return
        }
        #expect(override["content"] == .string("Overridden"))
    }

    // MARK: - Diagnostics

    @Test("Flattening a rich text node emits one diagnostic naming the node")
    func flatteningEmitsOneDiagnostic() throws {
        let collector = PenDiagnosticCollector()
        let document: [String: AnyCodable] = [
            "children": .array([richTextNode(id: "rich", runs: [
                ["content": .string("Bold "), "fontWeight": .string("700")],
                ["content": .string("Italic "), "fontStyle": .string("italic")],
            ])]),
        ]

        _ = migrate(document, diagnostics: collector)

        #expect(collector.diagnostics.count == 1)
        let diagnostic = try #require(collector.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.stage == .migration)
        #expect(diagnostic.nodeID == "rich")
        #expect(diagnostic.message.lowercased().contains("styling"))
    }

    @Test("Each flattened node gets its own diagnostic")
    func eachNodeGetsItsOwnDiagnostic() {
        let collector = PenDiagnosticCollector()
        let document: [String: AnyCodable] = [
            "children": .array([
                richTextNode(id: "first", runs: [["content": .string("a")]]),
                richTextNode(id: "second", runs: [["content": .string("b")]]),
            ]),
        ]

        _ = migrate(document, diagnostics: collector)

        #expect(collector.diagnostics.map(\.nodeID) == ["first", "second"])
    }

    @Test("A descendant override's diagnostic is keyed by its path")
    func descendantOverrideDiagnosticUsesThePath() {
        let collector = PenDiagnosticCollector()
        let document: [String: AnyCodable] = [
            "children": .array([.dictionary([
                "type": .string("ref"),
                "id": .string("ref1"),
                "ref": .string("card"),
                "descendants": .dictionary([
                    "card/label": .dictionary([
                        "content": .array([.dictionary(["content": .string("Hi")])]),
                    ]),
                ]),
            ])]),
        ]

        _ = migrate(document, diagnostics: collector)

        #expect(collector.diagnostics.map(\.nodeID) == ["card/label"])
    }

    @Test("Plain content emits no diagnostic")
    func plainContentEmitsNoDiagnostic() {
        let collector = PenDiagnosticCollector()
        let document: [String: AnyCodable] = [
            "children": .array([.dictionary([
                "type": .string("text"),
                "id": .string("plain"),
                "content": .string("Hello"),
            ])]),
        ]

        _ = migrate(document, diagnostics: collector)

        #expect(collector.diagnostics.isEmpty)
    }

    // MARK: - Registration

    @Test("The rule is registered with the migrator")
    func ruleIsRegistered() {
        #expect(PenLegacyMigrator.rules.contains { $0 is PenRichTextMigrationRule })
    }

    @Test("The full migrator flattens rich text end to end")
    func fullMigratorFlattensRichText() {
        let document: [String: AnyCodable] = [
            "version": .string("2.9"),
            "children": .array([richTextNode(id: "rich", runs: [
                ["content": .string("Bold ")],
                ["content": .string("Italic ")],
                ["content": .string("Colored")],
            ])]),
        ]

        let migrated = PenLegacyMigrator.migrate(document)

        #expect(content(of: migrated, at: [0]) == .string("Bold Italic Colored"))
    }
}
