//
//  PenMetadataTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct PenMetadataTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Round-trip

    @Test("PenMetadata round-trips through JSON with type + extensions")
    func roundTripWithExtensions() throws {
        let metadata = PenMetadata(type: "component", extensions: [
            "_role": .string("button"),
            "_action": .string("submit"),
        ])
        let data = try encoder.encode(metadata)
        let decoded = try decoder.decode(PenMetadata.self, from: data)

        #expect(decoded.type == "component")
        #expect(decoded.extensions["_role"] == .string("button"))
        #expect(decoded.extensions["_action"] == .string("submit"))
    }

    // MARK: - Backward compat

    @Test("Decoding without a type field leaves type nil")
    func decodingWithoutTypeLeavesTypeNil() throws {
        // Pen itself writes metadata objects with no `type` key (found by extras,
        // leaf VaJSI3); `type` used to default to "unknown" here, which turned a
        // read-modify-write round trip of such a file into a diff nothing asked for.
        let json = #"{"_role": "button"}"#
        let data = Data(json.utf8)
        let decoded = try decoder.decode(PenMetadata.self, from: data)

        #expect(decoded.type == nil)
        #expect(decoded.extensions["_role"] == .string("button"))
    }

    // MARK: - Encoding

    @Test("Encoding writes type when present")
    func encodingWritesTypeWhenPresent() throws {
        let metadata = PenMetadata(type: "component")
        let data = try encoder.encode(metadata)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["type"] as? String == "component")
    }

    @Test("Encoding omits type when absent, so a round trip adds no key")
    func encodingOmitsTypeWhenAbsent() throws {
        // The regression test for the round-trip bug: a metadata object read from a
        // file that never had `type` must come back out exactly as it went in.
        let json = #"{"_role": "button"}"#
        let data = Data(json.utf8)
        let decoded = try decoder.decode(PenMetadata.self, from: data)

        let reEncoded = try encoder.encode(decoded)
        let reEncodedJSON = try JSONSerialization.jsonObject(with: reEncoded) as? [String: Any]

        #expect(reEncodedJSON?["type"] == nil)
        #expect(reEncodedJSON?["_role"] as? String == "button")
    }

    // MARK: - Subscript

    @Test("Subscript access for extensions")
    func subscriptExtensions() {
        let metadata = PenMetadata(type: "component", extensions: [
            "_role": .string("button"),
        ])
        #expect(metadata["_role"] == .string("button"))
        #expect(metadata["_nonexistent"] == nil)
    }

    @Test("Subscript access for type returns .string")
    func subscriptType() {
        let metadata = PenMetadata(type: "component")
        #expect(metadata["type"] == .string("component"))
    }

    @Test("Subscript access for an absent type returns nil")
    func subscriptTypeAbsent() {
        let metadata = PenMetadata(type: nil)
        #expect(metadata["type"] == nil)
    }

    // MARK: - PenNodeCommon integration

    @Test("PenNodeCommon with PenMetadata round-trips")
    func penNodeCommonRoundTrip() throws {
        let common = PenNodeCommon(
            name: "MyNode",
            metadata: PenMetadata(type: "component", extensions: [
                "_role": .string("button"),
            ])
        )
        let node = PenNode(
            id: "n1",
            common: common,
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let data = try encoder.encode(node)
        let decoded = try decoder.decode(PenNode.self, from: data)

        #expect(decoded.common.metadata?.type == "component")
        #expect(decoded.common.metadata?["_role"] == .string("button"))
    }

    // MARK: - Wire format compatibility

    @Test("Wire format matches flat dictionary encoding")
    func wireFormatMatchesFlatDict() throws {
        let metadata = PenMetadata(type: "component", extensions: [
            "_role": .string("button"),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let metadataData = try encoder.encode(metadata)

        // The equivalent old-style dictionary
        let oldDict: [String: AnyCodable] = [
            "type": .string("component"),
            "_role": .string("button"),
        ]
        let oldData = try encoder.encode(oldDict)

        // Both should produce identical JSON
        #expect(metadataData == oldData)
    }

    // MARK: - Dictionary literal

    @Test("Dictionary literal creates PenMetadata correctly")
    func dictionaryLiteral() {
        let metadata: PenMetadata = [
            "type": .string("component"),
            "_role": .string("button"),
        ]
        #expect(metadata.type == "component")
        #expect(metadata.extensions["_role"] == .string("button"))
    }

    @Test("Dictionary literal without type leaves type nil")
    func dictionaryLiteralWithoutType() {
        let metadata: PenMetadata = ["_role": .string("button")]
        #expect(metadata.type == nil)
    }

    // MARK: - CRDT PropertyCodec

    @Test("CRDT PropertyCodec metadata round-trips")
    @MainActor
    func crdtPropertyCodecRoundTrip() throws {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(
                name: "Rect",
                metadata: PenMetadata(type: "component", extensions: ["_role": .string("button")])
            ),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let doc = PenDocument(children: [rect])
        let editable = EditableDocument(from: doc, peerID: PeerID(rawValue: "peer1"))

        // Update metadata
        let newMetadata = PenMetadata(type: "component", extensions: [
            "_role": .string("toggle"),
            "_action": .string("switch"),
        ])
        _ = try editable.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(
                name: "Rect",
                metadata: newMetadata
            ))
        ))

        #expect(editable.nodes["r1"]?.common.metadata?.type == "component")
        #expect(editable.nodes["r1"]?.common.metadata?["_role"] == .string("toggle"))
    }
}
