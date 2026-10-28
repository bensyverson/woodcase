//
//  PenShaderEffectTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers the format 2.21 shader effect (``PenEffect/shader(_:)``): it decodes from a file
/// enabled or disabled, re-encodes without loss, can be authored, shares its uniforms type
/// with the shader fill, and has its `$variable` uniforms resolved like the fill's.
struct PenShaderEffectTests {
    // MARK: - Helpers

    private func document(effect: String) -> Data {
        Data(#"""
        {"version":"2.21","children":[{"id":"R1","type":"rectangle","width":40,"height":40,"fill":"#3366FF",
          "effect":\#(effect)}]}
        """#.utf8)
    }

    private func effects(of document: PenDocument) throws -> [PenEffect] {
        guard case let .rectangle(data) = try #require(document.children.first).kind else {
            Issue.record("not a rectangle")
            return []
        }
        return data.effects?.all ?? []
    }

    /// The JSON value of `data`, for a comparison that ignores key order.
    private func json(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private static let enabledAndDisabled = #"""
    [{"type":"shader","url":"./post.frag","uniforms":{"u_strength":0.5,"u_on":true,"u_tint":"#FF8800",
       "u_offset":[1,2],"u_glow":"$glow"}},
     {"type":"shader","enabled":false,"url":"./other.frag"}]
    """#

    // MARK: - Decoding and round trip

    @Test("A 2.21 file's enabled and disabled shader effects decode to .shader")
    func decodesToShader() throws {
        let doc = try PenParser.parse(document(effect: Self.enabledAndDisabled))
        let all = try effects(of: doc)
        #expect(all.count == 2)
        guard case let .shader(on) = all.first, case let .shader(off) = all.last else {
            Issue.record("expected two shader effects, got \(all)")
            return
        }
        #expect(on.url == "./post.frag")
        #expect(on.enabled == nil)
        #expect(on.uniforms?["u_strength"] == .number(0.5))
        #expect(on.uniforms?["u_on"] == .bool(true))
        #expect(on.uniforms?["u_tint"] == .color("#FF8800"))
        #expect(on.uniforms?["u_offset"] == .vector([1, 2]))
        #expect(on.uniforms?["u_glow"] == .variable("glow"))
        #expect(off.url == "./other.frag")
        #expect(off.enabled == .literal(false))
        #expect(off.uniforms == nil)
    }

    @Test("A shader effect re-encodes without loss, unknown keys included")
    func roundTrips() throws {
        let effect = #"""
        [{"type":"shader","url":"./post.frag","uniforms":{"u_strength":0.5,"u_glow":"$glow","u_tex":"pencil:object"},
          "futureKey":{"a":1}},
         {"type":"shader","enabled":false,"url":"./other.frag"}]
        """#
        let original = document(effect: effect)
        let doc = try PenParser.parse(original)
        let encoded = try PenParser.encode(doc)
        #expect(try json(encoded) == json(original))
        guard case let .shader(on) = try effects(of: doc).first else {
            Issue.record("expected a shader effect")
            return
        }
        #expect(on.extras.keys.contains("futureKey"))
    }

    @Test("A shader effect is enabled unless it says otherwise")
    func enabledByDefault() {
        #expect(PenEffect.shader(PenEffect.PenShaderEffect(url: "a.frag")).isEnabled)
        #expect(!PenEffect.shader(PenEffect.PenShaderEffect(enabled: .literal(false), url: "a.frag")).isEnabled)
    }

    // MARK: - Authoring

    @Test("An agent can author a shader effect, and it is not .unknown")
    func authors() throws {
        let value = try JSONDecoder().decode(AnyCodable.self, from: Data(#"""
        [{"type":"shader","url":"./post.frag","uniforms":{"u_strength":0.5,"u_tint":"$brand"}}]
        """#.utf8))
        let node = PenNode(id: "n1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let patched = try NodePropertyCodec.setting(value, at: "kind.effects", on: node)
        guard case let .rectangle(data) = patched.kind, case let .shader(effect) = data.effects?.all.first else {
            Issue.record("expected a shader effect on the rectangle")
            return
        }
        #expect(effect.url == "./post.frag")
        #expect(effect.uniforms == ["u_strength": .number(0.5), "u_tint": .variable("brand")])
    }

    @Test("Authoring a shader effect without a url is refused")
    func authoringNeedsAURL() throws {
        let value = try JSONDecoder().decode(AnyCodable.self, from: Data(#"[{"type":"shader"}]"#.utf8))
        let node = PenNode(id: "n1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        #expect(throws: (any Error).self) {
            try NodePropertyCodec.setting(value, at: "kind.effects", on: node)
        }
    }

    @Test("Shader is one of the effect types the decoder names")
    func vocabulary() {
        #expect(PenEffect.effectTypeNames.contains("shader"))
    }

    // MARK: - One uniforms type

    @Test("The shader fill and the shader effect share one uniforms type")
    func sharedUniformsType() {
        let uniforms: PenShaderUniforms = ["u_strength": .number(0.5), "u_glow": .variable("glow")]
        let fill = PenFill.PenShaderFill(url: "a.frag", uniforms: uniforms)
        let effect = PenEffect.PenShaderEffect(url: "a.frag", uniforms: uniforms)
        let fillUniforms: PenShaderUniforms? = fill.uniforms
        let effectUniforms: PenShaderUniforms? = effect.uniforms
        #expect(fillUniforms == effectUniforms)
        #expect(type(of: fill.uniforms) == type(of: effect.uniforms))
    }

    // MARK: - Variable resolution

    @Test("A $variable uniform of a shader effect resolves as a shader fill's does")
    func resolvesUniformVariables() {
        let document = PenDocument(
            version: "2.21",
            variables: [
                "glow": PenVariable(type: .color, value: .simple(.string("#FF0000"))),
                "strength": PenVariable(type: .number, value: .simple(.double(0.75))),
                "on": PenVariable(type: .boolean, value: .simple(.bool(false))),
            ],
            children: [
                PenNode(
                    id: "r1", common: PenNodeCommon(),
                    kind: .rectangle(PenNode.RectangleData(effects: .single(.shader(PenEffect.PenShaderEffect(
                        enabled: .variable("on"),
                        url: "post.frag",
                        uniforms: ["u_glow": .variable("glow"), "u_strength": .variable("strength"), "u_n": .number(2)]
                    )))))
                ),
            ]
        )
        let resolved = PenVariableResolver.resolve(document)
        guard case let .rectangle(data) = resolved.children[0].kind, case let .shader(effect) = data.effects?.all.first else {
            Issue.record("expected a shader effect")
            return
        }
        #expect(effect.enabled == .literal(false))
        #expect(effect.uniforms?["u_glow"] == .color("#FF0000"))
        #expect(effect.uniforms?["u_strength"] == .number(0.75))
        #expect(effect.uniforms?["u_n"] == .number(2))
    }

    // MARK: - Schema

    @Test("The effect schema lists the shader effect with its url and uniforms")
    func schemaListsShader() throws {
        let variant = try #require(PenEffect.schema.variants.first { $0.spelling == "shader" })
        let keys = variant.fields.map(\.key)
        #expect(keys == ["enabled", "url", "uniforms"])
        let url = try #require(variant.fields.first { $0.key == "url" })
        #expect(url.isRequired)
        let fillVariant = try #require(PenFill.schema.variants.first { $0.spelling == "shader" })
        let fillUniforms = try #require(fillVariant.fields.first { $0.key == "uniforms" })
        let effectUniforms = try #require(variant.fields.first { $0.key == "uniforms" })
        #expect(fillUniforms == effectUniforms)
    }
}
