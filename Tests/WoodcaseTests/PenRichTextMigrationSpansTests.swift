//
//  PenRichTextMigrationSpansTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenRichTextMigrationRule`` on a 2.10 `text` node: the runs flatten into `content` as
/// before, and their styling moves to `metadata.woodcase.spans` instead of being discarded.
struct PenRichTextMigrationSpansTests {
    private func migrate(
        _ node: [String: AnyCodable], diagnostics: PenDiagnosticCollector? = nil
    ) throws -> [String: AnyCodable] {
        let document: [String: AnyCodable] = ["version": .string("2.9"), "children": .array([.dictionary(node)])]
        let migrated = PenLegacyMigrator.migrate(document, rules: [PenRichTextMigrationRule()], diagnostics: diagnostics)
        guard case let .array(children)? = migrated["children"], case let .dictionary(first)? = children.first else {
            Issue.record("no node after migration")
            return [:]
        }
        return first
    }

    private func text(_ runs: [[String: AnyCodable]], metadata: AnyCodable? = nil) -> [String: AnyCodable] {
        var node: [String: AnyCodable] = [
            "type": .string("text"), "id": .string("rich"), "content": .array(runs.map(AnyCodable.dictionary)),
        ]
        node["metadata"] = metadata
        return node
    }

    private func spans(of node: [String: AnyCodable]) -> PenTextSpans? {
        guard case let .dictionary(object)? = node["metadata"] else { return nil }
        return PenMetadata(object: object).textSpans
    }

    @Test("A text node's styled runs become spans over the joined string, in UTF-16 units")
    func runsBecomeSpans() throws {
        let collector = PenDiagnosticCollector()
        let migrated = try migrate(text([
            ["content": .string("👍🏽 Bold "), "fontWeight": .string("700"), "fill": .string("#FF0000")],
            ["content": .string("plain ")],
            ["content": .string("Italic"), "fontStyle": .string("italic"), "fontSize": .int(20),
             "fontFamily": .string("Inter"), "underline": .bool(true), "strikethrough": .bool(false)],
        ]), diagnostics: collector)

        #expect(migrated["content"] == .string("👍🏽 Bold plain Italic"))
        // "👍🏽 Bold " is 10 UTF-16 units (the toned thumbs-up is 4), "plain " 6, "Italic" 6.
        #expect(spans(of: migrated) == PenTextSpans(text: "👍🏽 Bold plain Italic", runs: [
            PenTextRun(start: 0, end: 10, fontWeight: 700, fill: PenHexColor(red: 255, green: 0, blue: 0)),
            PenTextRun(start: 16, end: 22, fontFamily: "Inter", fontSize: 20, isItalic: true, underline: true,
                       strikethrough: false),
        ]))
        guard case let .dictionary(metadata)? = migrated["metadata"] else { return }
        #expect(metadata["type"] == .string(PenMetadata.woodcaseType))
        #expect(collector.diagnostics.isEmpty)
    }

    @Test("Metadata the node already had is kept beside the spans")
    func keepsExistingMetadata() throws {
        let migrated = try migrate(text(
            [["content": .string("Hi"), "fontWeight": .string("bold")]],
            metadata: .dictionary(["type": .string("label"), "owner": .string("ana")])
        ))
        guard case let .dictionary(metadata)? = migrated["metadata"] else {
            Issue.record("metadata lost")
            return
        }
        #expect(metadata["type"] == .string("label"))
        #expect(metadata["owner"] == .string("ana"))
        #expect(spans(of: migrated)?.runs == [PenTextRun(start: 0, end: 2, fontWeight: 700)])
    }

    @Test("Unstyled runs flatten with no spans and no warning")
    func unstyledRunsMakeNoSpans() throws {
        let collector = PenDiagnosticCollector()
        let migrated = try migrate(text([["content": .string("a")], ["content": .string("b")]]), diagnostics: collector)
        #expect(migrated["content"] == .string("ab"))
        #expect(migrated["metadata"] == nil)
        #expect(collector.diagnostics.isEmpty)
    }

    @Test("Styling spans cannot hold is dropped with one warning naming it; the rest is kept")
    func uncarriedStylingWarns() throws {
        let collector = PenDiagnosticCollector()
        let migrated = try migrate(text([
            ["content": .string("Wide "), "letterSpacing": .int(2), "fontWeight": .string("700")],
            ["content": .string("sized"), "fontSize": .string("$big")],
        ]), diagnostics: collector)
        #expect(spans(of: migrated)?.runs == [PenTextRun(start: 0, end: 5, fontWeight: 700)])
        #expect(collector.diagnostics.count == 1)
        let message = try #require(collector.diagnostics.first?.message)
        #expect(message.contains("letterSpacing"))
        #expect(message.contains("fontSize"))
        #expect(collector.diagnostics.first?.nodeID == "rich")
    }
}
