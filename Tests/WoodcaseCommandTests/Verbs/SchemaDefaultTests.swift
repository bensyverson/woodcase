//
//  SchemaDefaultTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase schema` prints what each property is when a node leaves it unset, and the
/// constraint each nested key's numbers keep to — in the text tables and in the JSON.
@Suite("The schema prints unset defaults and nested constraints")
struct SchemaDefaultTests {
    /// The line for `path` in the DEFAULTS section of `text`: from its heading to the
    /// next blank line.
    private func row(_ path: String, in text: String, endingWith suffix: String) -> Substring? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let heading = lines.firstIndex(where: { $0.hasPrefix("DEFAULTS") }) else { return nil }
        let section = lines[(heading + 2)...].prefix { !$0.isEmpty }
        return section.first { $0.hasPrefix("  \(path) ") && $0.hasSuffix(suffix) }
    }

    @Test("A type's table lists every property's default, a literal or where it comes from")
    func typeDefaults() throws {
        let text = try SchemaHelp.text(for: "frame")
        #expect(text.contains("DEFAULTS"))
        #expect(row("kind.layout", in: text, endingWith: #""horizontal""#) != nil)
        #expect(row("kind.gap", in: text, endingWith: " 0") != nil)

        let typography = try SchemaHelp.text(for: "text")
        #expect(row("kind.fontSize", in: typography, endingWith: " 16") != nil)
        #expect(row("kind.lineHeight", in: typography, endingWith: "the font's own line height") != nil)
        #expect(try row("kind.fontSize", in: SchemaHelp.text(for: "note"), endingWith: " 13") != nil)
    }

    @Test("Every type prints every default its table lists")
    func everyDefault() throws {
        for type in PenNode.NodeType.allCases {
            let text = try SchemaHelp.text(for: type.rawValue)
            for property in PenSchema.table(for: type).properties {
                guard let unset = property.default else { continue }
                #expect(!unset.summary.isEmpty)
                #expect(row(property.path, in: text, endingWith: unset.summary) != nil,
                        "schema \(type.rawValue) does not print \(property.path)'s default")
            }
        }
    }

    @Test("The overview lists the common properties' defaults")
    func commonDefaults() throws {
        let text = try SchemaHelp.text(for: nil)
        #expect(row("common.opacity", in: text, endingWith: " 1") != nil)
        #expect(row("common.enabled", in: text, endingWith: " true") != nil)
    }

    @Test("The JSON carries each row's default as its literal, or where it comes from")
    func jsonDefaults() throws {
        let json = try SchemaHelp.json(for: "text")
        #expect(json.contains(#""default" : 16"#))
        #expect(json.contains(#""default" : "left""#))
        #expect(json.contains(#""defaultFrom" : "the font's own line height""#))
    }

    @Test("Nested key tables print each key's constraint")
    func nestedConstraintText() throws {
        let text = try SchemaHelp.text(for: "frame")
        let position = text.split(separator: "\n").first {
            $0.contains("position*") && $0.hasSuffix("0 to 1, a fraction")
        }
        #expect(position != nil)
        let radius = text.split(separator: "\n").first { $0.contains("radius ") && $0.hasSuffix("≥ 0, in points") }
        #expect(radius != nil)
    }

    @Test("The JSON carries each nested key's constraint")
    func nestedConstraintJSON() throws {
        let report = SchemaNestedReport(PenFill.stopSchema)
        let position = report.variants.first?.fields.first { $0.key == "position" }
        #expect(position?.constraint == "0 to 1, a fraction")
        let json = try SchemaHelp.json(for: "frame")
        #expect(json.contains(#""constraint" : "0 to 1, a fraction""#))
    }
}
