//
//  PenSchemaTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenSchema`` — the property vocabulary, assembled from the decoders.
///
/// Everything the schema publishes has a second source in the library: the paths come
/// from `PropertyDiff.allKindKeys`, the spellings from the enumerations that
/// decode them, the nested keys from the payload structs themselves. These tests hold
/// each half against the other, so a property added to a decoder and forgotten here
/// fails the suite rather than quietly vanishing from the help.
@Suite("The schema assembled from the decoders")
struct PenSchemaTests {
    // MARK: - Coverage

    @Test("A type's table names every kind path the codec accepts", arguments: PenNode.NodeType.allCases)
    func tableCoversEveryKindPath(type: PenNode.NodeType) {
        let table = PenSchema.table(for: type)
        #expect(Set(table.properties.map(\.path)) == PropertyDiff.allKindKeys(type))
    }

    @Test("The common table names every common path the codec accepts")
    func commonTableCoversEveryCommonPath() {
        #expect(Set(PenSchema.common.properties.map(\.path)) == NodePropertyCodec.commonPaths)
    }

    @Test("Every row carries the raw .pen key beside the codec path", arguments: PenNode.NodeType.allCases)
    func everyRowCarriesItsWireKey(type: PenNode.NodeType) {
        for property in PenSchema.table(for: type).properties where property.key != .inlined {
            let field = String(property.path.dropFirst("kind.".count))
            #expect(property.key.written == NodePropertyCodec.jsonKey(for: field))
        }
    }

    @Test("A ref's root overrides are shown as inlined keys, not a key of their own")
    func rootOverridesHaveNoWireKey() throws {
        let row = try #require(
            PenSchema.table(for: .ref).properties.first { $0.path == "kind.rootOverrides" }
        )
        #expect(row.key == .inlined)
        #expect(row.key.written == nil)
        #expect(!row.key.column.contains("rootOverrides"))
    }

    @Test("Every type has a one-phrase description", arguments: PenNode.NodeType.allCases)
    func everyTypeIsDescribed(type: PenNode.NodeType) {
        #expect(!type.summary.isEmpty)
        #expect(!type.summary.contains("\n"))
        #expect(type.summary.count <= 72, "\(type.rawValue)'s description is \(type.summary.count) characters")
    }

    // MARK: - Spellings come off the decoders

    /// A property whose values an enumeration decides, and that enumeration.
    static let enumeratedProperties: [(path: String, spellings: [String])] = [
        ("kind.textGrowth", PenTextGrowth.allCases.map(\.rawValue)),
        ("kind.textAlign", PenTextAlign.allCases.map(\.rawValue)),
        ("kind.textAlignVertical", PenTextAlignVertical.allCases.map(\.rawValue)),
        ("kind.layout", PenLayoutDirection.allCases.map(\.rawValue)),
        ("kind.justifyContent", PenJustifyContent.allCases.map(\.rawValue)),
        ("kind.alignItems", PenAlignItems.allCases.map(\.rawValue)),
        ("kind.fillRule", PenFillRule.allCases.map(\.rawValue)),
        ("kind.strokeLinecap", PenStrokeCap.allCases.map(\.rawValue)),
        ("kind.strokeLinejoin", PenStrokeJoin.allCases.map(\.rawValue)),
        ("kind.strokeAlignment", PenStrokeAlign.allCases.map(\.rawValue)),
    ]

    @Test("An enumerated property lists exactly the decoder's spellings", arguments: enumeratedProperties)
    func enumeratedPropertiesListTheirSpellings(property: (path: String, spellings: [String])) throws {
        let row = try #require(
            PenNode.NodeType.allCases
                .flatMap { PenSchema.table(for: $0).properties }
                .first { $0.path == property.path },
            "no type's table carries \(property.path)"
        )
        #expect(row.spellings == property.spellings)
        for spelling in property.spellings {
            #expect(row.value.contains("\"\(spelling)\""), "\(property.path) does not print \(spelling)")
        }
    }

    @Test("common.layoutPosition lists the decoder's spellings")
    func commonEnumeratedPropertyListsItsSpellings() throws {
        let row = try #require(PenSchema.common.properties.first { $0.path == "common.layoutPosition" })
        #expect(row.spellings == PenLayoutPosition.allCases.map(\.rawValue))
    }

    // MARK: - Variable acceptance

    /// A property that takes a `$variable`, and the variable type it must have.
    static let variableProperties: [(path: String, type: PenVariableType)] = [
        ("kind.content", .string),
        ("kind.fontSize", .number),
        ("kind.underline", .boolean),
        ("kind.fills", .color),
        ("kind.width", .number),
        ("kind.padding", .number),
    ]

    @Test("A property that takes a $variable names its type", arguments: variableProperties)
    func variablePropertiesNameTheirType(property: (path: String, type: PenVariableType)) throws {
        let row = try #require(
            PenNode.NodeType.allCases
                .flatMap { PenSchema.table(for: $0).properties }
                .first { $0.path == property.path }
        )
        #expect(row.variable == property.type)
        #expect(row.value.contains("$\(property.type.rawValue)"))
    }

    @Test("A property that takes no $variable says so")
    func nonVariablePropertiesCarryNoType() throws {
        let row = try #require(PenSchema.table(for: .text).properties.first { $0.path == "kind.textGrowth" })
        #expect(row.variable == nil)
        #expect(!row.value.contains("$"))
    }

    // MARK: - Nesting

    @Test("A fill is recursed into its variants, one per spelling the decoder takes")
    func fillShapeCoversEveryFillType() throws {
        let row = try #require(PenSchema.table(for: .frame).properties.first { $0.path == "kind.fills" })
        let shape = try #require(row.nested.first { $0.name == "fill" })
        #expect(shape.variants.compactMap(\.spelling) == PenFill.fillTypeNames)
    }

    @Test("A mesh gradient's points name both wire forms and recurse into the object's keys")
    func meshPointsAreSpelledOut() throws {
        let row = try #require(PenSchema.table(for: .frame).properties.first { $0.path == "kind.fills" })
        let fill = try #require(row.nested.first { $0.name == "fill" })
        let mesh = try #require(fill.variants.first { $0.spelling == "mesh_gradient" })
        let points = try #require(mesh.fields.first { $0.key == "points" })
        #expect(points.value == "[[x, y] | mesh point, …]")
        #expect(points.forms.map(\.phrase) == ["an array, each element [x, y] or a mesh point object"])

        let point = try #require(row.nested.first { $0.name == "mesh point" })
        let fields = try #require(point.variants.first).fields
        #expect(fields.map(\.key) == ["position", "leftHandle", "rightHandle", "topHandle", "bottomHandle"])
        #expect(fields.first?.isRequired == true)
        #expect(fields.first?.value == "[x, y]")
        #expect(fields.dropFirst().allSatisfy { $0.value == "[dx, dy]" && !$0.isRequired })
    }

    @Test("The mesh point table lists exactly the object form's stored keys")
    func meshPointTableMatchesItsPayload() throws {
        let shape = try #require(PenSchema.nestedShapes.first { $0.name == "mesh point" })
        let point = try JSONDecoder().decode(PenMeshPoint.self, from: Data(##"{"position":[0,0]}"##.utf8))
        let stored = Self.storedKeys(of: point)
        #expect(try Set(#require(shape.variants.first).fields.map(\.key)) == Set(stored))
    }

    @Test("An effect is recursed into its variants, one per spelling the decoder takes")
    func effectShapeCoversEveryEffectType() throws {
        let row = try #require(PenSchema.table(for: .frame).properties.first { $0.path == "kind.effects" })
        let shape = try #require(row.nested.first { $0.name == "effect" })
        #expect(shape.variants.compactMap(\.spelling) == PenEffect.effectTypeNames)
    }

    @Test("strokeWidth's per-side form is spelled out, and the decoder takes it")
    func perSideStrokeWidthIsSpelledOut() throws {
        let row = try #require(PenSchema.table(for: .frame).properties.first { $0.path == "kind.strokeWidth" })
        let shape = try #require(row.nested.first { $0.name == "per-side width" })
        let keys = shape.variants.flatMap { $0.fields.map(\.key) }
        #expect(keys == ["top", "right", "bottom", "left"])

        // The four keys are the four the decoder reads.
        let json = Data(##"{"top":1,"right":2,"bottom":3,"left":4}"##.utf8)
        let width = try JSONDecoder().decode(PenStrokeWidth.self, from: json)
        guard case let .perSide(sides) = width else {
            Issue.record("the per-side object did not decode as per-side")
            return
        }
        #expect([sides.top, sides.right, sides.bottom, sides.left].map { $0?.literalValue } == [1, 2, 3, 4])
    }

    /// A nested variant and a sample of the payload struct it describes.
    ///
    /// The sample is decoded from JSON rather than built, so the keys compared are the
    /// keys the *decoder* reads. `Mirror` then reports the payload's stored properties,
    /// which is what makes this a drift alarm: add a key to `PenShadowEffect` and the
    /// nested table that omits it fails here.
    static let nestedSamples: [(shape: String, spelling: String, json: String)] = [
        ("fill", "color", ##"{"type":"color","color":"#FFD166"}"##),
        ("fill", "gradient", ##"{"type":"gradient"}"##),
        ("fill", "image", ##"{"type":"image"}"##),
        ("fill", "mesh_gradient", ##"{"type":"mesh_gradient"}"##),
        ("fill", "shader", ##"{"type":"shader","url":"s.frag"}"##),
        ("effect", "blur", ##"{"type":"blur"}"##),
        ("effect", "background_blur", ##"{"type":"background_blur"}"##),
        ("effect", "shadow", ##"{"type":"shadow"}"##),
    ]

    @Test("A nested variant lists exactly the payload's own keys", arguments: nestedSamples)
    func nestedVariantsMatchTheirPayloads(sample: (shape: String, spelling: String, json: String)) throws {
        let shapes = PenSchema.nestedShapes
        let shape = try #require(shapes.first { $0.name == sample.shape })
        let variant = try #require(shape.variants.first { $0.spelling == sample.spelling })

        let data = Data(sample.json.utf8)
        let stored: [String] = if sample.shape == "fill" {
            try Self.storedKeys(of: JSONDecoder().decode(PenFill.self, from: data))
        } else {
            try Self.storedKeys(of: JSONDecoder().decode(PenEffect.self, from: data))
        }
        #expect(
            Set(variant.fields.map(\.key)) == Set(stored),
            "the \(sample.spelling) \(sample.shape) table lists \(variant.fields.map(\.key)), the payload holds \(stored)"
        )
    }

    /// The stored property names of the payload inside a single-payload enumeration case.
    ///
    /// `extras` is left out: it is not a key of the payload but the bag of keys the
    /// payload does *not* claim (``PenExtras``), so no schema table lists it.
    private static func storedKeys(of value: Any) -> [String] {
        guard let payload = Mirror(reflecting: value).children.first?.value else { return [] }
        return Mirror(reflecting: payload).children.compactMap(\.label).filter { $0 != "extras" }
    }

    // MARK: - The refusals still read as they did

    @Test("Typing the forms left every refusal's prose as it was")
    func proseIsUnchanged() {
        #expect(NodePropertyCodec.expectedShape(of: "width")
            == ##"a number, "fit_content", "fill_container", or a $variable"##)
        #expect(NodePropertyCodec.expectedShape(of: "padding")
            == "a number, a $variable, [vertical, horizontal], or [top, right, bottom, left], for example [12, 16]")
        #expect(NodePropertyCodec.expectedShape(of: "textGrowth")
            == ##""auto", "fixed-width", or "fixed-width-height""##)
    }

    /// A colour property takes a `$variable` and always did — the decoder reads
    /// ``PenFill/shorthand(_:)`` from any string, and the resolver treats a leading `$`
    /// as a reference. The refusal never said so, which is exactly the gap typing the
    /// forms exposed: a form the decoder accepts and the prose omitted.
    @Test("A paint property offers the $variable its decoder has always taken")
    func paintOffersItsVariable() throws {
        #expect(NodePropertyCodec.expectedShape(of: "fills") == """
        a color string, a $variable, a fill object, or an array of either \
        (a fill object's type is one of color, gradient, image, mesh_gradient, shader), \
        for example [{"type":"color","color":"#FFD166"}]
        """)

        let value = try JSONDecoder().decode(AnyCodable.self, from: Data(##""$brand""##.utf8))
        let node = PenNode(id: "n1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let patched = try NodePropertyCodec.setting(value, at: "kind.fills", on: node)
        guard case let .rectangle(data) = patched.kind else { Issue.record("not a rectangle"); return }
        #expect(data.fills == .single(.shorthand("$brand")))
    }
}
