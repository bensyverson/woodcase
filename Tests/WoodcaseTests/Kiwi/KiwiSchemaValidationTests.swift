//
//  KiwiSchemaValidationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A schema is compiled before any message is read: one that is truncated, refers to
/// nothing, or could never be decoded is a typed error, never a crash.
struct KiwiSchemaValidationTests {
    typealias Field = KiwiTestBytes.Field
    typealias Native = KiwiTestBytes.Native

    private static func expectError(_ expected: KiwiDecodingError, _ data: Data) {
        #expect(throws: expected) { try KiwiSchema(binary: data) }
    }

    @Test func refusesAnUnknownDefinitionKind() {
        Self.expectError(
            .invalidDefinitionKind(definition: "Odd", kind: 3),
            KiwiTestBytes.schema([("Odd", 3, [])])
        )
    }

    @Test func refusesATypeIndexPastTheDefinitions() {
        Self.expectError(
            .invalidFieldType(definition: "A", field: "next", type: 1),
            KiwiTestBytes.schema([("A", 2, [Field(name: "next", type: 1, value: 1)])])
        )
    }

    @Test func refusesANativeTypeNumberPastTheNativeTypes() {
        Self.expectError(
            .invalidFieldType(definition: "A", field: "odd", type: -9),
            KiwiTestBytes.schema([("A", 2, [Field(name: "odd", type: -9, value: 1)])])
        )
    }

    @Test func refusesDuplicateDefinitionNames() {
        Self.expectError(
            .duplicateDefinition("A"),
            KiwiTestBytes.schema([("A", 2, []), ("A", 1, [])])
        )
    }

    @Test func refusesDuplicateFieldNames() {
        Self.expectError(
            .duplicateFieldName(definition: "A", field: "x"),
            KiwiTestBytes.schema([("A", 2, [
                Field(name: "x", type: Native.bool, value: 1),
                Field(name: "x", type: Native.uint, value: 2),
            ])])
        )
    }

    @Test func refusesDuplicateFieldValues() {
        Self.expectError(
            .duplicateFieldValue(definition: "E", value: 4),
            KiwiTestBytes.schema([("E", 0, [
                Field(name: "ONE", type: 0, value: 4),
                Field(name: "TWO", type: 0, value: 4),
            ])])
        )
    }

    @Test func refusesAStructThatContainsItself() {
        Self.expectError(
            .recursiveStruct("A"),
            KiwiTestBytes.schema([("A", 1, [Field(name: "me", type: 0, value: 1)])])
        )
    }

    @Test func refusesAStructCycleThroughAnotherStruct() {
        let data = KiwiTestBytes.schema([
            ("Leaf", 1, [Field(name: "x", type: Native.float, value: 1)]),
            ("A", 1, [Field(name: "b", type: 2, value: 1)]),
            ("B", 1, [Field(name: "a", type: 1, value: 1), Field(name: "leaf", type: 0, value: 2)]),
        ])
        #expect(throws: KiwiDecodingError.self) { try KiwiSchema(binary: data) }
        do {
            _ = try KiwiSchema(binary: data)
        } catch let .recursiveStruct(name) {
            #expect(["A", "B"].contains(name))
        } catch {
            Issue.record("expected recursiveStruct, got \(error)")
        }
    }

    @Test func acceptsRecursionThroughAnArrayOrAMessage() throws {
        let data = KiwiTestBytes.schema([
            ("Tree", 1, [Field(name: "children", type: 0, isArray: true, value: 1)]),
            ("Node", 2, [Field(name: "parent", type: 1, value: 1)]),
        ])
        #expect(try KiwiSchema(binary: data).definitions.count == 2)
    }

    @Test func refusesADefinitionCountLargerThanTheInput() {
        var bytes = KiwiTestBytes()
        bytes.varUInt(1_000_000)
        bytes.string("A")
        Self.expectError(.countExceedsRemainingBytes(count: 1_000_000, offset: 0), bytes.data)
    }

    @Test func refusesTrailingBytesAfterTheLastDefinition() {
        var bytes = KiwiTestBytes(bytes: Array(KiwiTestBytes.schema([("A", 2, [])])))
        bytes.raw(0x00)
        Self.expectError(.trailingBytes(count: 1), bytes.data)
    }

    @Test func refusesAFieldTypeTheSchemaDoesNotDefine() {
        let definition = KiwiDefinition(name: "A", kind: .message, fields: [
            KiwiField(name: "b", type: .definition("Missing"), isArray: false, value: 1),
        ])
        #expect(throws: KiwiDecodingError.undefinedFieldType(definition: "A", field: "b", type: "Missing")) {
            try KiwiSchema(definitions: [definition])
        }
    }

    @Test func refusesAMessageFieldWithoutAType() {
        let definition = KiwiDefinition(name: "A", kind: .message, fields: [
            KiwiField(name: "b", type: nil, isArray: false, value: 1),
        ])
        #expect(throws: KiwiDecodingError.missingFieldType(definition: "A", field: "b")) {
            try KiwiSchema(definitions: [definition])
        }
    }

    @Test func everyTruncationOfTheFixtureSchemaIsATypedError() throws {
        let full = try KiwiFixtures.schemaData()
        // Every 997th prefix plus the first and last few: a full sweep is quadratic.
        let lengths = Set(Array(0 ..< 16) + Array(stride(from: 0, to: full.count, by: 997)) + Array((full.count - 16) ..< full.count))
        for length in lengths.sorted() {
            #expect(throws: KiwiDecodingError.self) { try KiwiSchema(binary: full.prefix(length)) }
        }
    }
}
