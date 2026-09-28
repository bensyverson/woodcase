//
//  PenShaderFillTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers the typed `shader` fill: ``PenFill/PenShaderFill`` and its
/// ``PenShaderUniform`` values decode and encode losslessly, and dispatch
/// through ``PenFill``'s Codable implementation like every other fill type.
struct PenShaderFillTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Fill-level dispatch

    @Test("A shader object decodes to PenFill.shader")
    func decodesAsShader() throws {
        let json = """
        {"type":"shader","enabled":true,"url":"effect.glsl",
         "uniforms":{"u_size":32,"u_color1":"#ffffff"}}
        """
        let fill = try decoder.decode(PenFill.self, from: Data(json.utf8))
        guard case let .shader(data) = fill else {
            Issue.record("Expected .shader, got \(fill)")
            return
        }
        #expect(data.enabled == .literal(true))
        #expect(data.url == "effect.glsl")
        #expect(data.uniforms?["u_size"] == .number(32))
        #expect(data.uniforms?["u_color1"] == .color("#ffffff"))
    }

    @Test("A shader fill round-trips through PenFill's Codable dispatch")
    func fillRoundTrips() throws {
        let fill = PenFill.shader(PenFill.PenShaderFill(
            enabled: .literal(true),
            blendMode: .multiply,
            opacity: .literal(0.8),
            url: "effect.glsl",
            uniforms: ["u_size": .number(32)]
        ))
        let data = try encoder.encode(fill)
        let decoded = try decoder.decode(PenFill.self, from: data)
        #expect(decoded == fill)
    }

    @Test("The .pen JSON key order for a shader fill round-trips its type field")
    func encodesTypeField() throws {
        let fill = PenFill.shader(PenFill.PenShaderFill(url: "effect.glsl"))
        let data = try encoder.encode(fill)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"type\":\"shader\""))
    }

    @Test("A shader fill inside PenFills round-trips")
    func fillsWrapperRoundTrips() throws {
        let fills = PenFills.single(.shader(PenFill.PenShaderFill(url: "effect.glsl")))
        let data = try encoder.encode(fills)
        let decoded = try decoder.decode(PenFills.self, from: data)
        #expect(decoded == fills)
    }

    // MARK: - PenShaderUniform scalar kinds

    @Test("PenShaderUniform decodes and encodes a number")
    func uniformNumber() throws {
        try assertRoundTrip(json: "32", expected: .number(32))
        try assertRoundTrip(json: "0.5", expected: .number(0.5))
    }

    @Test("PenShaderUniform decodes and encodes a bool")
    func uniformBool() throws {
        try assertRoundTrip(json: "true", expected: .bool(true))
    }

    @Test("PenShaderUniform decodes and encodes a hex color string")
    func uniformColor() throws {
        try assertRoundTrip(json: "\"#ffffff\"", expected: .color("#ffffff"))
        try assertRoundTrip(json: "\"#FF0000AA\"", expected: .color("#FF0000AA"))
    }

    @Test("PenShaderUniform decodes a $variable reference and encodes it back with the $ prefix")
    func uniformVariable() throws {
        let decoded = try decoder.decode(PenShaderUniform.self, from: Data("\"$glowColor\"".utf8))
        #expect(decoded == .variable("glowColor"))
        let reencoded = try encoder.encode(decoded)
        #expect(String(data: reencoded, encoding: .utf8) == "\"$glowColor\"")
    }

    @Test("PenShaderUniform decodes and encodes 2-4 component vectors")
    func uniformVectors() throws {
        try assertRoundTrip(json: "[1,2]", expected: .vector([1, 2]))
        try assertRoundTrip(json: "[1,2,3]", expected: .vector([1, 2, 3]))
        try assertRoundTrip(json: "[1,2,3,4]", expected: .vector([1, 2, 3, 4]))
    }

    @Test("PenShaderUniform rejects a vector outside 2-4 components")
    func uniformVectorOutOfRange() {
        #expect(throws: (any Error).self) {
            try self.decoder.decode(PenShaderUniform.self, from: Data("[1]".utf8))
        }
        #expect(throws: (any Error).self) {
            try self.decoder.decode(PenShaderUniform.self, from: Data("[1,2,3,4,5]".utf8))
        }
    }

    private func assertRoundTrip(
        json: String,
        expected: PenShaderUniform,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let decoded = try decoder.decode(PenShaderUniform.self, from: Data(json.utf8))
        #expect(decoded == expected, sourceLocation: sourceLocation)
        let reencoded = try encoder.encode(decoded)
        let redecoded = try decoder.decode(PenShaderUniform.self, from: reencoded)
        #expect(redecoded == expected, sourceLocation: sourceLocation)
    }
}
