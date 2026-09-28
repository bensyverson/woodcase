//
//  PenScriptDataTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers the typed `script` node: ``PenNode/ScriptData`` and its ``PenScriptInput``
/// values decode and encode losslessly, and dispatch through ``PenNode``'s Codable
/// implementation like every other node kind.
struct PenScriptDataTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Node-level dispatch

    @Test("A script node decodes to Kind.script")
    func decodesAsScript() throws {
        let json = """
        {"type":"script","id":"TqFEu","x":300,"y":250,"name":"probe-script",
         "width":100,"height":40,"scriptUri":"bars.js","inputs":{"rows":3,"color":"#3B82F6"}}
        """
        let node = try decoder.decode(PenNode.self, from: Data(json.utf8))
        guard case let .script(data) = node.kind else {
            Issue.record("Expected .script, got \(node.kind)")
            return
        }
        #expect(data.scriptUri == "bars.js")
        #expect(data.width == .fixed(100))
        #expect(data.height == .fixed(40))
        #expect(data.inputs?["rows"] == .number(3))
        #expect(data.inputs?["color"] == .string("#3B82F6"))
    }

    @Test("NodeType includes .script")
    func nodeTypeIncludesScript() {
        #expect(PenNode.NodeType(rawValue: "script") == .script)
    }

    @Test("A script node round-trips through PenNode's Codable dispatch")
    func nodeRoundTrips() throws {
        let node = PenNode(
            id: "s1",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .script(PenNode.ScriptData(
                scriptUri: "bars.js",
                inputs: ["rows": .number(3)],
                clip: .literal(true),
                width: .fixed(100),
                height: .fixed(40)
            ))
        )
        let data = try encoder.encode(node)
        let decoded = try decoder.decode(PenNode.self, from: data)
        #expect(decoded == node)
    }

    @Test("The .pen JSON key order for a script node round-trips its type field")
    func encodesTypeField() throws {
        let node = PenNode(
            id: "s1", common: PenNodeCommon(),
            kind: .script(PenNode.ScriptData(scriptUri: "bars.js"))
        )
        let data = try encoder.encode(node)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"type\":\"script\""))
    }

    // MARK: - ScriptData fields

    @Test("ScriptData decodes and encodes clip and size")
    func scriptDataClipAndSize() throws {
        let script = PenNode.ScriptData(
            clip: .literal(true),
            width: .fixed(100),
            height: .fixed(40)
        )
        let data = try encoder.encode(script)
        let decoded = try decoder.decode(PenNode.ScriptData.self, from: data)
        #expect(decoded == script)
    }

    @Test("ScriptData with no inputs decodes to nil, not an empty dictionary")
    func scriptDataNoInputs() throws {
        let json = #"{"width":10,"height":10}"#
        let decoded = try decoder.decode(PenNode.ScriptData.self, from: Data(json.utf8))
        #expect(decoded.inputs == nil)
        #expect(decoded.scriptUri == nil)
        #expect(decoded.clip == nil)
    }

    // MARK: - PenScriptInput scalar kinds

    @Test("PenScriptInput decodes and encodes a number")
    func scriptInputNumber() throws {
        try assertRoundTrip(json: "3", expected: .number(3))
        try assertRoundTrip(json: "3.5", expected: .number(3.5))
    }

    @Test("PenScriptInput decodes and encodes a string")
    func scriptInputString() throws {
        try assertRoundTrip(json: "\"hello\"", expected: .string("hello"))
    }

    @Test("PenScriptInput decodes and encodes a hex color string as a plain string")
    func scriptInputColorString() throws {
        try assertRoundTrip(json: "\"#3B82F6\"", expected: .string("#3B82F6"))
    }

    @Test("PenScriptInput decodes and encodes a bool")
    func scriptInputBool() throws {
        try assertRoundTrip(json: "true", expected: .bool(true))
        try assertRoundTrip(json: "false", expected: .bool(false))
    }

    @Test("PenScriptInput decodes a $variable reference and encodes it back with the $ prefix")
    func scriptInputVariable() throws {
        let decoded = try decoder.decode(PenScriptInput.self, from: Data("\"$rowCount\"".utf8))
        #expect(decoded == .variable("rowCount"))
        let reencoded = try encoder.encode(decoded)
        #expect(String(data: reencoded, encoding: .utf8) == "\"$rowCount\"")
    }

    private func assertRoundTrip(
        json: String,
        expected: PenScriptInput,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let decoded = try decoder.decode(PenScriptInput.self, from: Data(json.utf8))
        #expect(decoded == expected, sourceLocation: sourceLocation)
        let reencoded = try encoder.encode(decoded)
        let redecoded = try decoder.decode(PenScriptInput.self, from: reencoded)
        #expect(redecoded == expected, sourceLocation: sourceLocation)
    }
}
