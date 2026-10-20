//
//  FigmaBlobTableTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `FigmaBlobTable` reads a message's `blobs` and hands out each one by the `uint` index a
/// node stores, decoded as the kind of blob that field names.
struct FigmaBlobTableTests {
    /// A committed case's message, decoded.
    static func message(_ caseID: String) throws -> KiwiRecord {
        try KiwiFixtures.schema().decode(KiwiFixtures.messageData(caseID), as: KiwiFixtures.rootType)
    }

    /// The `nodeChanges` of a committed case.
    static func nodes(_ caseID: String) throws -> [KiwiValue] {
        try message(caseID)["nodeChanges"]?.arrayValue ?? []
    }

    /// The node named `name` in a committed case.
    static func node(_ name: String, in caseID: String) throws -> KiwiValue {
        try #require(nodes(caseID).first { $0["name"]?.stringValue == name }, "\(name) in \(caseID)")
    }

    @Test("The table holds each blob's bytes, in message order")
    func tableBytes() throws {
        let table = try FigmaBlobTable(message: Self.message("V1"))
        #expect(table.blobs.map(\.count) == [156, 380, 244, 244, 380, 124, 80])
        #expect(try table.blob(at: 6).count == 80)
    }

    @Test("A message with no blobs has an empty table")
    func noBlobs() throws {
        let table = try FigmaBlobTable(message: Self.message("G1"))
        #expect(table.blobs.isEmpty)
    }

    @Test("An index past the table is refused")
    func indexOutOfRange() throws {
        let table = try FigmaBlobTable(message: Self.message("V1"))
        #expect(throws: FigmaBlobError.blobIndexOutOfRange(index: 7, count: 7)) {
            try table.blob(at: 7)
        }
        #expect(throws: FigmaBlobError.blobIndexOutOfRange(index: .max, count: 7)) {
            try table.vectorNetwork(at: .max)
        }
    }

    @Test("A blobs field that is not an array of Blob structs is refused")
    func malformedTable() throws {
        let notArray = KiwiRecord(typeName: "Message", fields: ["blobs": .uint(3)])
        #expect(throws: FigmaBlobError.malformedBlobTable) {
            try FigmaBlobTable(message: notArray)
        }
        let noBytes = KiwiRecord(typeName: "Message", fields: [
            "blobs": .array([.structure(KiwiRecord(typeName: "Blob", fields: [:]))]),
        ])
        #expect(throws: FigmaBlobError.malformedBlobTable) {
            try FigmaBlobTable(message: noBytes)
        }
    }

    @Test("A blob base index, which no clipboard has set, is refused rather than guessed at")
    func blobBaseIndex() throws {
        let based = KiwiRecord(typeName: "Message", fields: ["blobBaseIndex": .uint(4), "blobs": .array([])])
        #expect(throws: FigmaBlobError.unsupportedBlobBaseIndex(4)) {
            try FigmaBlobTable(message: based)
        }
        let zero = KiwiRecord(typeName: "Message", fields: ["blobBaseIndex": .uint(0), "blobs": .array([])])
        #expect(try FigmaBlobTable(message: zero).blobs.isEmpty)
    }

    @Test("A node's vectorNetworkBlob index decodes to its network")
    func vectorNetworkByIndex() throws {
        let node = try Self.node("V1a closed filled triangle", in: "V1")
        let index = try #require(node["vectorData"]?["vectorNetworkBlob"]?.uintValue)
        let network = try FigmaBlobTable(message: Self.message("V1")).vectorNetwork(at: index)
        #expect(network.vertices.map(\.position) == [
            FigmaPoint(x: 0, y: 80), FigmaPoint(x: 40, y: 0), FigmaPoint(x: 80, y: 80),
        ])
        #expect(network.regions.map(\.windingRule) == [.nonzero])
    }

    @Test("A vertex's style id names an entry of the node's styleOverrideTable")
    func vertexStyleIDs() throws {
        let table = try FigmaBlobTable(message: Self.message("V1"))
        for name in ["V1a closed filled triangle", "V1g open curves", "V1c flattened donut"] {
            let vectorData = try #require(Self.node(name, in: "V1")["vectorData"])
            let network = try table.vectorNetwork(at: #require(vectorData["vectorNetworkBlob"]?.uintValue))
            let overrides = Set((vectorData["styleOverrideTable"]?.arrayValue ?? []).compactMap { $0["styleID"]?.uintValue })
            for vertex in network.vertices where vertex.styleID != 0 {
                #expect(overrides.contains(vertex.styleID), "\(name): style \(vertex.styleID)")
            }
            #expect(network.segments.allSatisfy { $0.styleID == 0 }, "\(name)")
        }
    }

    @Test("Identical glyphs share one blob, so several glyphs name the same index")
    func glyphReuse() throws {
        let glyphs = try Self.nodes("T1").flatMap { $0["derivedTextData"]?["glyphs"]?.arrayValue ?? [] }
        let indices = glyphs.compactMap { $0["commandsBlob"]?.uintValue }
        let table = try FigmaBlobTable(message: Self.message("T1"))
        #expect(indices.count > Set(indices).count)
        #expect(Set(indices).count == table.blobs.count)
    }
}
