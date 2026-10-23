//
//  SchemaNoteTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase schema` says what a nested key's numbers mean when no range or unit can —
/// an image fill's crop `transform` — in the text tables and in the JSON, so a writer
/// cannot get its units wrong.
@Suite("The schema prints what a nested key's numbers mean")
struct SchemaNoteTests {
    /// The formula an agent needs to crop a pixel rect.
    private static let formula = "[W/cw, 0, 0, H/ch, -cx/cw, -cy/ch]"

    @Test("The image fill's transform line says its units and how to crop a pixel rect")
    func transformNoteText() throws {
        let text = try SchemaHelp.text(for: "rectangle")
        let lines = text.split(separator: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("  fill —") })
        let block = lines[(start + 1)...].prefix { !$0.hasPrefix("  ") || $0.hasPrefix("    ") }
        let image = try #require(block.firstIndex { $0.contains(#""type": "image""#) })
        let transform = try #require(block[image...].first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("transform")
        })
        #expect(transform.contains("unit square"), "\(transform)")
        #expect(transform.contains(Self.formula), "\(transform)")
    }

    @Test("The JSON carries the transform's note")
    func transformNoteJSON() throws {
        let report = SchemaNestedReport(PenFill.schema)
        let image = try #require(report.variants.first { $0.spelling == "image" })
        let transform = try #require(image.fields.first { $0.key == "transform" })
        #expect(transform.note?.contains(Self.formula) == true)
        #expect(try SchemaHelp.json(for: "rectangle").contains(#""note" : "#))
    }

    @Test("A key with nothing more to say carries no note")
    func noNoteByDefault() throws {
        let report = SchemaNestedReport(PenFill.schema)
        let image = try #require(report.variants.first { $0.spelling == "image" })
        #expect(image.fields.first { $0.key == "url" }?.note == nil)
    }
}
