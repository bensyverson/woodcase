//
//  PenExtrasDecodingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers ``PenExtras`` at the model: a file decode keeps every key the typed model
/// does not claim — at the root, on a node, on each fill and effect, and on a stroke's
/// paint — and every `type` it does not recognize, and writes them back unchanged.
/// Authoring input, decoded in ``PenDecodingMode/authoring``, refuses the same keys.
struct PenExtrasDecodingTests {
    // MARK: - Helpers

    /// The fixture every level of extras is exercised on.
    static var fixtureURL: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "preserved-extras", withExtension: "pen", subdirectory: "Fixtures"))
        }
    }

    /// Parses the fixture the way a file is read.
    static func fixture() throws -> PenDocument {
        try PenParser.parse(contentsOf: fixtureURL)
    }

    /// A JSON value, for semantic comparison of two encodings.
    static func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    /// Decodes one value the way an agent's input is decoded.
    static func authored<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        return try decoder.decode(type, from: Data(json.utf8))
    }

    /// Decodes one value the way a file is decoded.
    static func filed<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func board(in document: PenDocument) throws -> PenNode.FrameData {
        let board = try #require(document.children.first { $0.id == "Board" })
        guard case let .frame(data) = board.kind else {
            Issue.record("Board is not a frame")
            throw CancellationError()
        }
        return data
    }

    // MARK: - Round trip

    @Test("A file with unknowns at every level encodes back semantically identical")
    func fileRoundTripsSemantically() throws {
        let original = try Data(contentsOf: Self.fixtureURL)
        let written = try PenParser.encode(PenParser.parse(original))
        #expect(try Self.object(written) == Self.object(original))
    }

    @Test("Root keys the model does not claim are document extras")
    func rootExtras() throws {
        let document = try Self.fixture()
        #expect(document.extras["futureRootKey"] == ["a": 1])
        // `fonts` was an extra until the model typed it; its own unknown key is now the
        // declaration's extra.
        #expect(document.extras["fonts"] == nil)
        #expect(document.fonts?.first?.extras["futureFontKey"] == 1)
        #expect(document.extras["children"] == nil)
        #expect(document.extras["version"] == nil)
    }

    @Test("Node keys the node's type does not claim are node extras")
    func nodeExtras() throws {
        let document = try Self.fixture()
        let board = try #require(document.children.first { $0.id == "Board" })
        #expect(board.extras.values == ["futureNodeKey": ["nested": [1, 2]]])
        let card = try #require(try Self.board(in: document).children?.first { $0.id == "Card1" })
        #expect(card.extras.values == ["futureChildKey": "kept"])
    }

    @Test("Fill, stroke-paint and effect keys land on the payload that carried them")
    func payloadExtras() throws {
        let data = try Self.board(in: Self.fixture())
        let fills = try #require(data.fills?.all)
        guard case let .color(color) = fills.first else {
            Issue.record("fill[0] is not a color fill: \(fills)")
            return
        }
        #expect(color.extras.values == ["futureFillKey": true])

        guard case let .color(stroke) = data.stroke?.all.first else {
            Issue.record("stroke is not a color fill: \(String(describing: data.stroke))")
            return
        }
        #expect(stroke.extras.values == ["futureStrokeKey": "s"])

        let effects = try #require(data.effects?.all)
        guard case let .shadow(shadow) = effects[0],
              case let .blur(blur) = effects[1],
              case let .backgroundBlur(backdrop) = effects[2]
        else {
            Issue.record("unexpected effects: \(effects)")
            return
        }
        #expect(shadow.extras.values == ["futureShadowKey": 7])
        #expect(blur.extras.values == ["futureBlurKey": 1])
        #expect(backdrop.extras.values == ["futureBackdropKey": 2])
    }

    @Test("An unrecognized fill type is kept verbatim as .unknown")
    func unknownFillType() throws {
        let fills = try #require(try Self.board(in: Self.fixture()).fills?.all)
        #expect(fills[1] == .unknown(typeName: "hologram", payload: PenExtras(["shimmer": 0.5])))
    }

    @Test("An unrecognized effect type is kept verbatim as .unknown, not fatal")
    func unknownEffectType() throws {
        let effects = try #require(try Self.board(in: Self.fixture()).effects?.all)
        #expect(effects[3] == .unknown(typeName: "glow", payload: PenExtras(["radius": 9, "spreadColor": "#FF00FF"])))
    }

    @Test("Every gradient, image, mesh and shader fill keeps its own extras")
    func everyFillVariantKeepsExtras() throws {
        let json = """
        [{"type":"gradient","gradientType":"linear","x1":1},
         {"type":"image","url":"a.png","x2":2},
         {"type":"mesh_gradient","columns":2,"rows":2,"x3":3},
         {"type":"shader","url":"s.glsl","x4":4}]
        """
        let fills = try Self.filed([PenFill].self, json)
        let extras: [PenExtras] = fills.map {
            switch $0 {
            case let .gradient(fill): fill.extras
            case let .image(fill): fill.extras
            case let .meshGradient(fill): fill.extras
            case let .shader(fill): fill.extras
            default: PenExtras()
            }
        }
        #expect(extras == [PenExtras(["x1": 1]), PenExtras(["x2": 2]), PenExtras(["x3": 3]), PenExtras(["x4": 4])])
        let reencoded = try JSONEncoder().encode(fills)
        #expect(try JSONSerialization.jsonObject(with: reencoded) as? NSArray
            == JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSArray)
    }

    @Test("A node carrying only modeled keys has no extras")
    func modeledKeysAreNeverExtras() throws {
        let json = """
        {"id":"F","type":"frame","name":"F","x":1,"y":2,"rotation":3,"opacity":0.5,"enabled":true,
         "flipX":false,"flipY":false,"reusable":false,"theme":{"mode":"dark"},"context":"c",
         "layoutPosition":"absolute","metadata":{"k":"v"},
         "width":10,"height":10,"cornerRadius":2,"clip":true,"fill":"#FFF","stroke":"#000",
         "strokeWidth":1,"strokeLinecap":"round","strokeLinejoin":"bevel","strokeAlignment":"inner",
         "effect":{"type":"blur","radius":1},"blendMode":"normal","layout":"vertical","gap":4,
         "padding":2,"justifyContent":"center","alignItems":"center","children":[]}
        """
        let node = try Self.filed(PenNode.self, json)
        #expect(node.extras.isEmpty)
    }

    @Test("A ref's unclaimed keys stay root overrides, never extras")
    func refKeysAreRootOverrides() throws {
        let node = try Self.filed(PenNode.self, #"{"id":"R","type":"ref","ref":"C","width":5,"future":1}"#)
        #expect(node.extras.isEmpty)
        guard case let .ref(data) = node.kind else {
            Issue.record("not a ref")
            return
        }
        #expect(data.rootOverrides?["future"] == 1)
    }

    @Test("An unknown node type keeps its keys as properties, not extras")
    func unknownNodeKeepsProperties() throws {
        let node = try Self.filed(PenNode.self, #"{"id":"G","type":"gizmo","width":3,"knob":1}"#)
        #expect(node.extras.isEmpty)
        #expect(node.kind == .unknown(typeName: "gizmo", properties: ["width": 3, "knob": 1]))
    }

    // MARK: - PenExtras itself

    @Test("PenExtras encodes as the plain object it holds")
    func extrasEncodeAsAnObject() throws {
        let extras = PenExtras(["b": 2, "a": [true]])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try String(decoding: encoder.encode(extras), as: UTF8.self) == #"{"a":[true],"b":2}"#)
        #expect(try Self.filed(PenExtras.self, #"{"a":[true],"b":2}"#) == extras)
    }

    @Test("PenExtras lists its keys sorted")
    func extrasKeysAreSorted() {
        #expect(PenExtras(["zeta": 1, "alpha": 2]).keys == ["alpha", "zeta"])
        #expect(PenExtras().isEmpty)
    }

    // MARK: - Authoring stays strict

    @Test("Authoring refuses an unknown key on a node, naming it")
    func authoringRefusesNodeKey() {
        #expect {
            _ = try Self.authored(PenNode.self, ##"{"id":"F","type":"frame","fil":"#FFF"}"##)
        } throws: { error in
            DecodingReason.describe(error).contains("fil")
        }
    }

    @Test("Authoring refuses an unknown key on a fill")
    func authoringRefusesFillKey() {
        #expect(throws: DecodingError.self) {
            _ = try Self.authored(PenFill.self, ##"{"type":"color","color":"#FFF","colour":"#000"}"##)
        }
    }

    @Test("Authoring refuses an unknown key on an effect")
    func authoringRefusesEffectKey() {
        #expect(throws: DecodingError.self) {
            _ = try Self.authored(PenEffect.self, #"{"type":"shadow","blurr":3}"#)
        }
    }

    @Test("Authoring refuses an unknown fill type")
    func authoringRefusesFillType() {
        #expect(throws: DecodingError.self) {
            _ = try Self.authored(PenFill.self, ##"{"type":"solid","color":"#FFF"}"##)
        }
    }

    @Test("Authoring refuses an unknown effect type")
    func authoringRefusesEffectType() {
        #expect(throws: DecodingError.self) {
            _ = try Self.authored(PenEffect.self, #"{"type":"glow","radius":3}"#)
        }
    }

    @Test("Authoring refuses an unknown node type, naming it and every real type")
    func authoringRefusesNodeType() {
        #expect {
            _ = try Self.authored(PenNode.self, #"{"id":"V","type":"video_clip","src":"a.mp4"}"#)
        } throws: { error in
            let reason = DecodingReason.describe(error)
            return reason.contains("video_clip") && reason.contains("frame") && reason.contains("connection")
        }
    }

    @Test("Authoring refuses an unknown node type nested in a subtree")
    func authoringRefusesNestedNodeType() {
        #expect(throws: DecodingError.self) {
            _ = try PenSubtreeDecoder.node(from: [
                "type": "frame", "name": "Hero",
                "children": [["type": "video_clip", "name": "Clip"]],
            ])
        }
    }

    @Test("A file keeps an unknown node type, whatever authoring does")
    func fileKeepsNodeType() throws {
        let node = try Self.filed(PenNode.self, #"{"id":"V","type":"video_clip","src":"a.mp4"}"#)
        #expect(node.kind == .unknown(typeName: "video_clip", properties: ["src": "a.mp4"]))
    }

    @Test("Authoring refuses an unknown key at the document root")
    func authoringRefusesRootKey() {
        #expect(throws: DecodingError.self) {
            _ = try Self.authored(PenDocument.self, #"{"version":"2.17","children":[],"extra":1}"#)
        }
    }

    @Test("The authored subtree decoder is strict")
    func subtreeDecoderIsStrict() {
        #expect(throws: DecodingError.self) {
            _ = try PenSubtreeDecoder.node(from: ["type": "frame", "name": "Hero", "fil": "#FFF"])
        }
        #expect(throws: DecodingError.self) {
            _ = try PenSubtreeDecoder.node(from: [
                "type": "frame", "name": "Hero",
                "children": [["type": "rectangle", "name": "R", "fill": ["type": "color", "color": "#FFF", "x": 1]]],
            ])
        }
    }
}
