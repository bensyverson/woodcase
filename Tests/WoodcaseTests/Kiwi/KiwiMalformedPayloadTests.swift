//
//  KiwiMalformedPayloadTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A clipboard can be written by anyone: a truncated, corrupted or hostile message is a
/// typed `KiwiDecodingError`, never a crash, a hang or an unbounded allocation.
struct KiwiMalformedPayloadTests {
    typealias Field = KiwiTestBytes.Field
    typealias Native = KiwiTestBytes.Native

    /// A message that may contain itself, an enum, a struct and an array of structs.
    private static let schema: KiwiSchema = {
        let data = KiwiTestBytes.schema([
            ("Mood", 0, [Field(name: "CALM", type: 0, value: 0)]),
            ("Point", 1, [Field(name: "x", type: Native.float, value: 1)]),
            ("Node", 2, [
                Field(name: "child", type: 2, value: 1),
                Field(name: "mood", type: 0, value: 2),
                Field(name: "points", type: 1, isArray: true, value: 3),
                Field(name: "name", type: Native.string, value: 4),
            ]),
            ("Empty", 1, []),
            ("Many", 2, [Field(name: "empties", type: 3, isArray: true, value: 1)]),
        ])
        return try! KiwiSchema(binary: data)
    }()

    private static func expectError(_ expected: KiwiDecodingError, _ bytes: [UInt8], as root: String = "Node") {
        #expect(throws: expected) { try schema.decode(Data(bytes), as: root) }
    }

    @Test func refusesAnUnknownRootType() {
        Self.expectError(.unknownType("Nope"), [0], as: "Nope")
    }

    @Test func refusesAnEnumerationAsTheRoot() {
        Self.expectError(.enumerationRoot("Mood"), [0], as: "Mood")
    }

    @Test func refusesAFieldValueTheMessageDoesNotDeclare() {
        Self.expectError(.unknownField(message: "Node", value: 9, offset: 0), [9, 0])
    }

    @Test func refusesAnEnumValueTheEnumerationDoesNotDeclare() {
        Self.expectError(.unknownEnumValue(enumeration: "Mood", value: 5, offset: 1), [2, 5, 0])
    }

    @Test func refusesAMessageWithoutItsTerminator() {
        Self.expectError(.truncated(offset: 2), [2, 0])
    }

    @Test func refusesBytesAfterTheRoot() {
        Self.expectError(.trailingBytes(count: 2), [0, 7, 7])
    }

    @Test func refusesAnArrayCountLargerThanTheInput() {
        Self.expectError(.countExceedsRemainingBytes(count: 1000, offset: 1), [3, 0xE8, 0x07, 0])
    }

    @Test func boundsAnArrayOfEmptyStructsByTheInput() throws {
        // Elements that take no bytes cannot make a count of a billion cheap to honor.
        var bytes = KiwiTestBytes()
        bytes.raw(1)
        bytes.varUInt(1_000_000_000)
        bytes.raw(0)
        #expect(throws: KiwiDecodingError.countExceedsRemainingBytes(count: 1_000_000_000, offset: 1)) {
            try Self.schema.decode(bytes.data, as: "Many")
        }
        let few = try Self.schema.decode(Data([1, 1, 0]), as: "Many")
        #expect(few["empties"] == .array([.structure(KiwiRecord(typeName: "Empty", fields: [:]))]))
    }

    @Test func capsNestingDepth() throws {
        // `child` nested 100 deep: legal Kiwi, but past a cap of 64.
        let deep = [UInt8](repeating: 1, count: 100) + [UInt8](repeating: 0, count: 101)
        Self.expectError(.depthLimitExceeded(limit: KiwiSchema.defaultMaxDepth), deep)
        #expect(throws: KiwiDecodingError.depthLimitExceeded(limit: 8)) {
            try Self.schema.decode(Data([1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), as: "Node", maxDepth: 8)
        }
        let shallow = [UInt8](repeating: 1, count: 10) + [UInt8](repeating: 0, count: 11)
        #expect(try Self.schema.decode(Data(shallow), as: "Node")["child"] != nil)
    }

    @Test func survivesAHostileDepthWithoutRecursingIntoIt() {
        // A million nested children must fail at the cap, long before the stack would.
        let hostile = [UInt8](repeating: 1, count: 1_000_000) + [0]
        Self.expectError(.depthLimitExceeded(limit: KiwiSchema.defaultMaxDepth), hostile)
    }

    @Test(arguments: [("M1b", 1), ("V1", 13)])
    func everyTruncationOfAFixtureMessageIsATypedError(caseID: String, stride step: Int) throws {
        // Every prefix of the small M1b; every 13th of V1, which has arrays, blobs and text.
        let schema = try KiwiFixtures.schema()
        let full = try KiwiFixtures.messageData(caseID)
        for length in stride(from: 0, to: full.count, by: step) {
            #expect(throws: KiwiDecodingError.self) {
                try schema.decode(full.prefix(length), as: KiwiFixtures.rootType)
            }
        }
    }

    @Test func survivesEveryByteOfAFixtureMessageCorrupted() throws {
        // Any outcome but a crash is acceptable; most corruptions are typed errors.
        let schema = try KiwiFixtures.schema()
        let full = try KiwiFixtures.messageData("M1b")
        var failures = 0
        for index in full.indices {
            for replacement: UInt8 in [0x00, 0x7F, 0x80, 0xFF] where full[index] != replacement {
                var corrupted = full
                corrupted[index] = replacement
                do {
                    _ = try schema.decode(corrupted, as: KiwiFixtures.rootType)
                } catch {
                    failures += 1
                }
            }
        }
        #expect(failures > 0)
    }
}
