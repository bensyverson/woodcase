//
//  KiwiMessageDecodingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `KiwiSchema.decode(_:as:)` turns a message into typed values, reading the schema it is
/// given rather than any built-in definitions.
///
/// The expected values for the fixtures come from the reference implementation
/// (`kiwi-schema` 0.5.0, via `scripts/kiwi-oracle`), which also consumed every
/// byte of every message. M1b's opening bytes were checked by hand: `01 01` type =
/// NODE_CHANGES, `0c fe ab b2 d1 0a` pasteID (zigzag) = 1,427,524,351, and
/// `0d 88 00 00 18 …` pasteOffset.x = 560.
struct KiwiMessageDecodingTests {
    private static func decode(_ caseID: String) throws -> KiwiRecord {
        try KiwiFixtures.schema().decode(KiwiFixtures.messageData(caseID), as: KiwiFixtures.rootType)
    }

    // MARK: - The fixture envelope

    @Test func decodesTheRootTypeAndEnvelope() throws {
        let message = try Self.decode("M1b")
        #expect(message.typeName == KiwiFixtures.rootType)
        #expect(message["type"] == .enumeration("NODE_CHANGES"))
        #expect(message["sessionID"] == .uint(0))
        #expect(message["pasteID"] == .int(1_427_524_351))
        #expect(message["pasteFileKey"] == .string("FixtureFileKey00000000"))
        #expect(message["pasteIsPartiallyOutsideEnclosingFrame"] == .bool(false))
        #expect(message["pasteEditorType"]?.enumName == "DESIGN")
        #expect(message["sentTimestamp"] == nil)
        let offset = try #require(message["pasteOffset"]?.recordValue)
        #expect(offset.typeName == "Vector")
        #expect(offset["x"] == .float(560))
        #expect(offset["y"] == .float(2360))
        #expect(message["publishedAssetGuids"] == .array([]))
    }

    @Test func confirmsTheCutCapture() throws {
        #expect(try Self.decode("M1b")["isCut"] == .bool(true))
        #expect(try Self.decode("M1a")["isCut"] == .bool(false))
    }

    @Test func decodesNestedMessagesStructsAndArrays() throws {
        let message = try Self.decode("M1b")
        let nodes = try #require(message["nodeChanges"]?.arrayValue)
        #expect(nodes.count == 4)
        #expect(nodes.compactMap { $0["name"]?.stringValue } == ["Document", "Page 1", "M1b cut target", "Internal Only Canvas"])
        let target = try #require(nodes[2].recordValue)
        #expect(target.typeName == "NodeChange")
        #expect(target["type"] == .enumeration("ROUNDED_RECTANGLE"))
        #expect(target["guid"]?["sessionID"] == .uint(1))
        #expect(target["guid"]?["localID"] == .uint(487))
        #expect(target["size"]?["x"] == .float(80))
        #expect(target["size"]?["y"] == .float(60))
        #expect(target["transform"]?["m02"] == .float(620))
        #expect(target["transform"]?["m12"] == .float(2390))
        #expect(target["parentIndex"]?["position"] == .string("!"))
        let paint = try #require(target["fillPaints"]?.arrayValue?.first)
        #expect(paint["type"] == .enumeration("SOLID"))
        #expect(paint["color"]?["r"] == .float(0.184_313_729_405_403_14))
        #expect(paint["color"]?["g"] == .float(0.619_607_865_810_394_3))
        #expect(paint["color"]?["a"] == .float(1))
        #expect(nodes[3]["visible"] == .bool(false))
        #expect(nodes[3]["internalOnly"] == .bool(true))
        let region = try #require(message["clipboardSelectionRegions"]?.arrayValue?.first)
        #expect(region["nodes"]?.arrayValue?.first?["localID"] == .uint(487))
        #expect(region["focusType"] == .enumeration("NONE"))
    }

    /// Node and blob counts and total blob bytes per case, from the reference decoder.
    @Test(arguments: [
        ("C1", 19, 22, 5858), ("G1", 30, 0, 0), ("I1", 10, 0, 0), ("L1", 28, 0, 0),
        ("M1a", 5, 0, 0), ("M1b", 4, 0, 0), ("M1c", 5, 0, 0), ("M1d", 7, 0, 0),
        ("M1e", 24, 0, 0), ("M1f", 103, 0, 0), ("P1", 42, 2, 248), ("R1", 18, 10, 3188),
        ("T1", 15, 43, 12129), ("V1", 26, 7, 1608),
    ])
    func decodesEveryFixture(caseID: String, nodes: Int, blobs: Int, blobBytes: Int) throws {
        let message = try Self.decode(caseID)
        #expect(message["type"] == .enumeration("NODE_CHANGES"))
        #expect(message["nodeChanges"]?.arrayValue?.count == nodes)
        let blobValues = message["blobs"]?.arrayValue ?? []
        #expect(blobValues.count == blobs)
        #expect(blobValues.reduce(0) { $0 + ($1["bytes"]?.bytesValue?.count ?? 0) } == blobBytes)
    }

    // MARK: - Synthetic payloads

    typealias Field = KiwiTestBytes.Field
    typealias Native = KiwiTestBytes.Native

    /// A schema with an enum, a struct of every native type and a message wrapping them.
    private static let syntheticSchema = KiwiTestBytes.schema([
        ("Mood", 0, [Field(name: "CALM", type: 0, value: 0), Field(name: "LOUD", type: 0, value: 7)]),
        ("All", 1, [
            Field(name: "b", type: Native.bool, value: 1),
            Field(name: "y", type: Native.byte, value: 2),
            Field(name: "i", type: Native.int, value: 3),
            Field(name: "u", type: Native.uint, value: 4),
            Field(name: "f", type: Native.float, value: 5),
            Field(name: "s", type: Native.string, value: 6),
            Field(name: "i64", type: Native.int64, value: 7),
            Field(name: "u64", type: Native.uint64, value: 8),
        ]),
        ("Box", 2, [
            Field(name: "all", type: 1, value: 1),
            Field(name: "moods", type: 0, isArray: true, value: 2),
            Field(name: "raw", type: Native.byte, isArray: true, value: 3),
            Field(name: "ints", type: Native.int, isArray: true, value: 4),
            Field(name: "inner", type: 2, value: 5),
        ]),
    ])

    @Test func decodesEveryNativeTypeInAStruct() throws {
        var bytes = KiwiTestBytes()
        bytes.raw(1, 0x01, 0xAB) // all: b, y
        bytes.varInt(-300)
        bytes.varUInt(300)
        bytes.raw(0x80, 0x01, 0x00, 0x40) // -2.5
        bytes.string("ok")
        bytes.varInt(Int64.min)
        bytes.varUInt(UInt64.max)
        bytes.raw(0) // end of Box
        let box = try KiwiSchema(binary: Self.syntheticSchema).decode(bytes.data, as: "Box")
        let all = try #require(box["all"]?.recordValue)
        #expect(all.typeName == "All")
        #expect(all.fields == [
            "b": .bool(true), "y": .byte(0xAB), "i": .int(-300), "u": .uint(300), "f": .float(-2.5),
            "s": .string("ok"), "i64": .int64(Int64.min), "u64": .uint64(UInt64.max),
        ])
        #expect(box["all"] == .structure(all))
    }

    @Test func decodesEnumArraysByteArraysAndNestedMessages() throws {
        var bytes = KiwiTestBytes()
        bytes.raw(2, 2, 7, 0) // moods: LOUD, CALM
        bytes.raw(3, 3, 9, 8, 7) // raw
        bytes.raw(4, 2, 0x03, 0x04) // ints: -2, 2
        bytes.raw(5, 2, 1, 0, 0) // inner: { moods: [CALM] }
        bytes.raw(0)
        let box = try KiwiSchema(binary: Self.syntheticSchema).decode(bytes.data, as: "Box")
        #expect(box["moods"] == .array([.enumeration("LOUD"), .enumeration("CALM")]))
        #expect(box["raw"] == .bytes(Data([9, 8, 7])))
        #expect(box["ints"] == .array([.int(-2), .int(2)]))
        #expect(box["inner"] == .message(KiwiRecord(typeName: "Box", fields: ["moods": .array([.enumeration("CALM")])])))
        #expect(box["all"] == nil)
    }

    @Test func decodesAStructAsTheRoot() throws {
        var bytes = KiwiTestBytes()
        bytes.raw(0, 0)
        bytes.varInt(1)
        bytes.varUInt(2)
        bytes.raw(0)
        bytes.string("")
        bytes.varInt(0)
        bytes.varUInt(0)
        let all = try KiwiSchema(binary: Self.syntheticSchema).decode(bytes.data, as: "All")
        #expect(all["f"] == .float(0))
        #expect(all["i"] == .int(1))
    }

    @Test func keepsTheLastValueOfARepeatedField() throws {
        let box = try KiwiSchema(binary: Self.syntheticSchema).decode(Data([3, 1, 5, 3, 1, 6, 0]), as: "Box")
        #expect(box["raw"] == .bytes(Data([6])))
    }
}
