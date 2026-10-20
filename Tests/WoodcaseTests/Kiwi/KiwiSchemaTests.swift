//
//  KiwiSchemaTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `KiwiSchema(binary:)` reads a binary schema into its definitions.
///
/// The fixture's counts and names come from the reference implementation
/// (`kiwi-schema` 0.5.0, via `scripts/kiwi-oracle`); the definition count's leading bytes,
/// `99 05` = 665, and the first definition, `MessageType` (kind 0, `19` = 25 fields), were
/// also read by hand from the file.
struct KiwiSchemaTests {
    @Test func decodesTheFixtureSchemaToItsDefinitionCounts() throws {
        let schema = try KiwiFixtures.schema()
        #expect(schema.definitions.count == 665)
        let kinds = Dictionary(grouping: schema.definitions, by: \.kind).mapValues(\.count)
        #expect(kinds[.enumeration] == 216)
        #expect(kinds[.message] == 419)
        #expect(kinds[.structure] == 30)
        #expect(schema.definitions.reduce(0) { $0 + $1.fields.count } == 4219)
    }

    @Test func keepsTheDefinitionsInFileOrder() throws {
        let schema = try KiwiFixtures.schema()
        #expect(schema.definitions.first?.name == "MessageType")
        #expect(schema.definitions.last?.name == "AudioTrack")
        #expect(schema.definitions.firstIndex { $0.name == KiwiFixtures.rootType } == 487)
        let structs = schema.definitions.filter { $0.kind == .structure }.map(\.name)
        #expect(Array(structs.prefix(4)) == ["GUID", "Color", "Vector", "Rect"])
        #expect(structs.last == "IndexEmojis")
    }

    @Test func readsEnumerationCases() throws {
        let schema = try KiwiFixtures.schema()
        let messageType = try #require(schema.definition(named: "MessageType"))
        #expect(messageType.kind == .enumeration)
        #expect(messageType.fields.count == 25)
        #expect(messageType.fields.prefix(4).map(\.name) == ["JOIN_START", "NODE_CHANGES", "USER_CHANGES", "JOIN_END"])
        #expect(messageType.fields.prefix(4).map(\.value) == [0, 1, 2, 3])
        #expect(messageType.fields.allSatisfy { $0.type == nil })
        #expect(schema.definition(named: "NodeType")?.field(named: "ROUNDED_RECTANGLE")?.value == 12)
    }

    @Test func readsMessageFieldsWithTheirTypes() throws {
        let schema = try KiwiFixtures.schema()
        let root = try #require(schema.definition(named: KiwiFixtures.rootType))
        #expect(root.kind == .message)
        #expect(root.fields.count == 49)
        let expected: [KiwiField] = [
            KiwiField(name: "type", type: .definition("MessageType"), isArray: false, value: 1),
            KiwiField(name: "sessionID", type: .uint, isArray: false, value: 2),
            KiwiField(name: "stableSessionID", type: .string, isArray: false, value: 42),
            KiwiField(name: "ackID", type: .uint, isArray: false, value: 3),
            KiwiField(name: "isRetransmission", type: .bool, isArray: false, value: 37),
            KiwiField(name: "nodeChanges", type: .definition("NodeChange"), isArray: true, value: 4),
        ]
        #expect(Array(root.fields.prefix(6)) == expected)
        #expect(root.field(named: "sentTimestamp")?.type == .uint64)
        #expect(schema.definition(named: "NodeChange")?.fields.count == 619)
        #expect(schema.definition(named: "NodeChange")?.field(named: "timelinePosition")?.type == .int64)
    }

    @Test func readsStructFieldsWithTheirTypes() throws {
        let schema = try KiwiFixtures.schema()
        let vector = try #require(schema.definition(named: "Vector"))
        #expect(vector.kind == .structure)
        #expect(vector.fields.map(\.name) == ["x", "y"])
        #expect(vector.fields.map(\.type) == [.float, .float])
        let blob = try #require(schema.definition(named: "Blob"))
        #expect(blob.fields == [KiwiField(name: "bytes", type: .byte, isArray: true, value: 1)])
    }

    @Test func returnsNilForAnUnknownDefinitionName() throws {
        #expect(try KiwiFixtures.schema().definition(named: "NoSuchDefinition") == nil)
    }

    @Test func decodesAHandBuiltSchemaOfEveryNativeType() throws {
        typealias Field = KiwiTestBytes.Field
        typealias Native = KiwiTestBytes.Native
        let natives: [(Int64, KiwiFieldType)] = [
            (Native.bool, .bool), (Native.byte, .byte), (Native.int, .int), (Native.uint, .uint),
            (Native.float, .float), (Native.string, .string), (Native.int64, .int64), (Native.uint64, .uint64),
        ]
        let fields = natives.enumerated().map { index, native in
            Field(name: "f\(index)", type: native.0, isArray: index.isMultiple(of: 2), value: UInt64(index + 1))
        }
        let data = KiwiTestBytes.schema([("Everything", 2, fields)])
        let schema = try KiwiSchema(binary: data)
        let definition = try #require(schema.definitions.first)
        #expect(definition.fields.map(\.type) == natives.map(\.1))
        #expect(definition.fields.map(\.isArray) == natives.indices.map { $0.isMultiple(of: 2) })
    }

    @Test func roundTripsThroughCodable() throws {
        let schema = try KiwiFixtures.schema()
        let encoded = try JSONEncoder().encode(schema)
        #expect(try JSONDecoder().decode(KiwiSchema.self, from: encoded) == schema)
    }
}
