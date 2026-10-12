//
//  PenSchemaFieldTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `PenSchema.fields(for:)` and `field(_:for:)`: the editable fields of a node type,
/// read from the same schema tables `woodcase schema` prints.
struct PenSchemaFieldTests {
    @Test("A type's fields are the common rows and its own, sorted by path", arguments: PenNode.NodeType.allCases)
    func fieldsAreBothTables(type: PenNode.NodeType) {
        let expected = (PenSchema.common.properties + PenSchema.table(for: type).properties)
            .sorted { $0.path < $1.path }
        #expect(PenSchema.fields(for: type) == expected)
    }

    @Test("A field carries its spellings, constraint, variable type and nested tables")
    func controlShape() throws {
        let growth = try #require(PenSchema.field("kind.textGrowth", for: .text))
        #expect(growth.spellings == ["auto", "fixed-width", "fixed-width-height"])

        let opacity = try #require(PenSchema.field("common.opacity", for: .text))
        #expect(opacity.constraint?.unit == .fraction)
        #expect(opacity.variable == .number)

        let fills = try #require(PenSchema.field("kind.fills", for: .frame))
        #expect(fills.variable == .color)
        #expect(fills.nested.map(\.name).contains("fill"))
    }

    @Test("A field is found by its path or its raw key")
    func byPathOrRawKey() {
        #expect(PenSchema.field("fill", for: .rectangle)?.path == "kind.fills")
        #expect(PenSchema.field("kind.fills", for: .rectangle)?.path == "kind.fills")
        #expect(PenSchema.field("opacity", for: .text)?.path == "common.opacity")
    }

    @Test("A property the type does not take is no field of it")
    func notAField() {
        #expect(PenSchema.field("kind.content", for: .rectangle) == nil)
        #expect(PenSchema.field("content", for: .rectangle) == nil)
        #expect(PenSchema.field("nonsense", for: .text) == nil)
    }
}
