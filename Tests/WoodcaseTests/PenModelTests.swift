//
//  PenModelTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-03-22.
//

import Foundation
import Testing
import Woodcase

struct PenModelTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - AnyCodable

    @Test("AnyCodable round-trips all JSON types")
    func anyCodableRoundTrip() throws {
        let values: [AnyCodable] = [
            .null,
            .bool(true),
            .bool(false),
            .int(42),
            .double(3.14),
            .string("hello"),
            .array([.int(1), .string("two"), .bool(false)]),
            .dictionary(["key": .string("value"), "nested": .array([.int(1)])]),
        ]

        for value in values {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(AnyCodable.self, from: data)
            #expect(decoded == value, "Round-trip failed for \(value)")
        }
    }

    @Test("AnyCodable literal initializers")
    func anyCodableLiterals() {
        let n: AnyCodable = nil
        let b: AnyCodable = true
        let i: AnyCodable = 42
        let d: AnyCodable = 3.14
        let s: AnyCodable = "hello"
        let a: AnyCodable = [1, 2, 3]
        let dict: AnyCodable = ["key": "value"]

        #expect(n == .null)
        #expect(b == .bool(true))
        #expect(i == .int(42))
        #expect(d == .double(3.14))
        #expect(s == .string("hello"))
        #expect(a == .array([.int(1), .int(2), .int(3)]))
        #expect(dict == .dictionary(["key": .string("value")]))
    }

    // MARK: - PenBlendMode

    @Test("PenBlendMode round-trips known modes")
    func blendModeKnown() throws {
        let modes: [PenBlendMode] = [
            .normal, .darken, .multiply, .linearBurn, .colorBurn,
            .light, .screen, .linearDodge, .colorDodge,
            .overlay, .softLight, .hardLight,
            .difference, .exclusion, .hue, .saturation, .color, .luminosity,
        ]

        for mode in modes {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(PenBlendMode.self, from: data)
            #expect(decoded == mode, "Round-trip failed for \(mode.rawString)")
        }
    }

    @Test("PenBlendMode preserves unknown values")
    func blendModeUnknown() throws {
        let mode = PenBlendMode.unknown("futureBlend")
        let data = try encoder.encode(mode)
        let decoded = try decoder.decode(PenBlendMode.self, from: data)
        #expect(decoded == .unknown("futureBlend"))
    }

    @Test("PenBlendMode decodes from JSON string")
    func blendModeFromJSON() throws {
        let json = Data(#""multiply""#.utf8)
        let decoded = try decoder.decode(PenBlendMode.self, from: json)
        #expect(decoded == .multiply)
    }

    // MARK: - PenSizing

    @Test("PenSizing decodes fixed number")
    func sizingFixed() throws {
        let json = Data("200".utf8)
        let decoded = try decoder.decode(PenSizing.self, from: json)
        #expect(decoded == .fixed(200))
    }

    @Test("PenSizing decodes fit_content without fallback")
    func sizingFitContent() throws {
        let json = Data(#""fit_content""#.utf8)
        let decoded = try decoder.decode(PenSizing.self, from: json)
        #expect(decoded == .fitContent(fallback: nil))
    }

    @Test("PenSizing decodes fit_content with integer fallback")
    func sizingFitContentFallback() throws {
        let json = Data(#""fit_content(200)""#.utf8)
        let decoded = try decoder.decode(PenSizing.self, from: json)
        #expect(decoded == .fitContent(fallback: 200))
    }

    @Test("PenSizing decodes fit_content with decimal fallback")
    func sizingFitContentDecimalFallback() throws {
        let json = Data(#""fit_content(100.5)""#.utf8)
        let decoded = try decoder.decode(PenSizing.self, from: json)
        #expect(decoded == .fitContent(fallback: 100.5))
    }

    @Test("PenSizing decodes fill_container without fallback")
    func sizingFillContainer() throws {
        let json = Data(#""fill_container""#.utf8)
        let decoded = try decoder.decode(PenSizing.self, from: json)
        #expect(decoded == .fillContainer(fallback: nil))
    }

    @Test("PenSizing decodes fill_container with fallback")
    func sizingFillContainerFallback() throws {
        let json = Data(#""fill_container(300)""#.utf8)
        let decoded = try decoder.decode(PenSizing.self, from: json)
        #expect(decoded == .fillContainer(fallback: 300))
    }

    @Test("PenSizing decodes variable reference")
    func sizingVariable() throws {
        let json = Data(#""$spacing.large""#.utf8)
        let decoded = try decoder.decode(PenSizing.self, from: json)
        #expect(decoded == .variable("spacing.large"))
    }

    @Test("PenSizing round-trips all variants")
    func sizingRoundTrip() throws {
        let values: [PenSizing] = [
            .fixed(100),
            .fixed(0),
            .fitContent(fallback: nil),
            .fitContent(fallback: 200),
            .fillContainer(fallback: nil),
            .fillContainer(fallback: 300),
            .variable("spacing.large"),
        ]

        for value in values {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenSizing.self, from: data)
            #expect(decoded == value, "Round-trip failed for \(value)")
        }
    }

    // MARK: - PenValue

    @Test("PenValue<Double> decodes literal number")
    func penValueDoubleLiteral() throws {
        let json = Data("0.8".utf8)
        let decoded: PenValue<Double> = try decoder.decode(PenValue<Double>.self, from: json)
        #expect(decoded == .literal(0.8))
    }

    @Test("PenValue<Double> decodes variable reference")
    func penValueDoubleVariable() throws {
        let json = Data(#""$opacity.default""#.utf8)
        let decoded: PenValue<Double> = try decoder.decode(PenValue<Double>.self, from: json)
        #expect(decoded == .variable("opacity.default"))
    }

    @Test("PenValue<String> decodes plain string")
    func penValueStringLiteral() throws {
        let json = Data(#""Hello World""#.utf8)
        let decoded: PenValue<String> = try decoder.decode(PenValue<String>.self, from: json)
        #expect(decoded == .literal("Hello World"))
    }

    @Test("PenValue<String> decodes variable reference")
    func penValueStringVariable() throws {
        let json = Data(##""$color.primary""##.utf8)
        let decoded: PenValue<String> = try decoder.decode(PenValue<String>.self, from: json)
        #expect(decoded == .variable("color.primary"))
    }

    @Test("PenValue<String> decodes a backslash-escaped $ as the literal, not a variable")
    func penValueStringEscapedDollarIsLiteral() throws {
        // The JSON text `"\\$v-muted"` holds the four-character Swift string `\$v-muted`.
        let json = Data(##""\\$v-muted""##.utf8)
        let decoded: PenValue<String> = try decoder.decode(PenValue<String>.self, from: json)
        #expect(decoded == .literal("$v-muted"))
    }

    @Test("PenValue<String> encodes a literal starting with $ escaped")
    func penValueStringLiteralDollarEncodesEscaped() throws {
        let value: PenValue<String> = .literal("$v-muted")
        let data = try encoder.encode(value)
        #expect(String(decoding: data, as: UTF8.self) == ##""\\$v-muted""##)
    }

    @Test("PenValue<String> a literal starting with $ round-trips through the escape")
    func penValueStringEscapedDollarRoundTrips() throws {
        let value: PenValue<String> = .literal("$v-muted")
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(PenValue<String>.self, from: data)
        #expect(decoded == value)
    }

    @Test("PenValue<String> a leading backslash not followed by $ is left alone")
    func penValueStringPlainBackslashUnaffected() throws {
        // Regression guard: the escape is specifically `\$`, so ordinary content that
        // happens to start with a backslash for some other reason must decode exactly
        // as it did before the escape existed.
        let json = Data(##""\\hello""##.utf8)
        let decoded: PenValue<String> = try decoder.decode(PenValue<String>.self, from: json)
        #expect(decoded == .literal(##"\hello"##))
    }

    @Test("PenValue<String> a literal that itself begins with \\$ loses the backslash after one round trip")
    func penValueStringLiteralBackslashDollarIsLossy() throws {
        // Known, documented limit: `\$` is Woodcase's own convention layered on a
        // format with no escape character of its own. Content whose first two
        // characters are already a literal backslash then `$` is indistinguishable
        // from an escaped `$` after one encode/decode cycle, and the backslash is
        // dropped. This pins that behavior as intentional rather than a surprise.
        let value: PenValue<String> = .literal(##"\$hi"##)
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(PenValue<String>.self, from: data)
        #expect(decoded == .literal("$hi"))
    }

    @Test("PenValue<Bool> decodes literal boolean")
    func penValueBoolLiteral() throws {
        let json = Data("true".utf8)
        let decoded: PenValue<Bool> = try decoder.decode(PenValue<Bool>.self, from: json)
        #expect(decoded == .literal(true))
    }

    @Test("PenValue<Bool> decodes variable reference")
    func penValueBoolVariable() throws {
        let json = Data(#""$show.title""#.utf8)
        let decoded: PenValue<Bool> = try decoder.decode(PenValue<Bool>.self, from: json)
        #expect(decoded == .variable("show.title"))
    }

    @Test("PenValue round-trips preserve type and value")
    func penValueRoundTrip() throws {
        let doubleVal: PenValue<Double> = .literal(42.5)
        let doubleVar: PenValue<Double> = .variable("size")
        let stringVal: PenValue<String> = .literal("hello")
        let stringVar: PenValue<String> = .variable("name")
        let boolVal: PenValue<Bool> = .literal(false)
        let boolVar: PenValue<Bool> = .variable("enabled")

        for value in [doubleVal, doubleVar] as [PenValue<Double>] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenValue<Double>.self, from: data)
            #expect(decoded == value)
        }
        for value in [stringVal, stringVar] as [PenValue<String>] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenValue<String>.self, from: data)
            #expect(decoded == value)
        }
        for value in [boolVal, boolVar] as [PenValue<Bool>] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenValue<Bool>.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("PenValue convenience accessors")
    func penValueAccessors() {
        let lit: PenValue<Double> = .literal(42.0)
        let varRef: PenValue<Double> = .variable("size")

        #expect(lit.literalValue == 42.0)
        #expect(lit.variableName == nil)
        #expect(varRef.literalValue == nil)
        #expect(varRef.variableName == "size")
    }

    // MARK: - PenPadding

    @Test("PenPadding decodes uniform number")
    func paddingUniform() throws {
        let json = Data("16".utf8)
        let decoded = try decoder.decode(PenPadding.self, from: json)
        #expect(decoded == .uniform(.literal(16)))
    }

    @Test("PenPadding decodes uniform variable")
    func paddingUniformVariable() throws {
        let json = Data(#""$spacing.md""#.utf8)
        let decoded = try decoder.decode(PenPadding.self, from: json)
        #expect(decoded == .uniform(.variable("spacing.md")))
    }

    @Test("PenPadding decodes 2-element array")
    func paddingSymmetric() throws {
        let json = Data("[16, 24]".utf8)
        let decoded = try decoder.decode(PenPadding.self, from: json)
        #expect(decoded == .symmetric(h: .literal(24), v: .literal(16)))
    }

    @Test("PenPadding decodes 4-element array")
    func paddingIndividual() throws {
        let json = Data("[8, 16, 24, 32]".utf8)
        let decoded = try decoder.decode(PenPadding.self, from: json)
        #expect(decoded == .individual(
            top: .literal(8),
            right: .literal(16),
            bottom: .literal(24),
            left: .literal(32)
        ))
    }

    @Test("PenPadding resolves to concrete edges")
    func paddingResolve() {
        let uniform = PenPadding.uniform(.literal(10))
        let edges = uniform.resolve()
        #expect(edges?.top == 10)
        #expect(edges?.right == 10)
        #expect(edges?.bottom == 10)
        #expect(edges?.left == 10)
        #expect(edges?.horizontal == 20)
        #expect(edges?.vertical == 20)
    }

    @Test("PenPadding resolve returns nil for unresolved variables")
    func paddingResolveVariable() {
        let padding = PenPadding.uniform(.variable("spacing"))
        #expect(padding.resolve() == nil)
    }

    @Test("PenPadding round-trips all variants")
    func paddingRoundTrip() throws {
        let values: [PenPadding] = [
            .uniform(.literal(16)),
            .uniform(.variable("spacing")),
            .symmetric(h: .literal(24), v: .literal(16)),
            .individual(top: .literal(8), right: .literal(16), bottom: .literal(24), left: .literal(32)),
        ]

        for value in values {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenPadding.self, from: data)
            #expect(decoded == value, "Round-trip failed for \(value)")
        }
    }

    // MARK: - PenRect

    @Test("PenRect round-trip and CGRect conversion")
    func penRect() throws {
        let rect = PenRect(x: 10, y: 20, width: 300, height: 200)
        let data = try encoder.encode(rect)
        let decoded = try decoder.decode(PenRect.self, from: data)
        #expect(decoded == rect)

        let cgRect = rect.cgRect
        #expect(cgRect.origin.x == 10)
        #expect(cgRect.origin.y == 20)
        #expect(cgRect.size.width == 300)
        #expect(cgRect.size.height == 200)
    }

    // MARK: - PenEnums

    @Test("PenLayoutDirection round-trips")
    func layoutDirection() throws {
        for dir in [PenLayoutDirection.none, .vertical, .horizontal] {
            let data = try encoder.encode(dir)
            let decoded = try decoder.decode(PenLayoutDirection.self, from: data)
            #expect(decoded == dir)
        }
    }

    @Test("PenJustifyContent round-trips including snake_case")
    func justifyContent() throws {
        let values: [PenJustifyContent] = [.start, .center, .end, .spaceBetween, .spaceAround]
        for value in values {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenJustifyContent.self, from: data)
            #expect(decoded == value)
        }

        // Verify snake_case encoding
        let data = try encoder.encode(PenJustifyContent.spaceBetween)
        let json = String(data: data, encoding: .utf8)
        #expect(json == #""space_between""#)
    }

    @Test("PenTextGrowth round-trips with hyphenated values")
    func textGrowth() throws {
        let values: [PenTextGrowth] = [.auto, .fixedWidth, .fixedWidthHeight]
        for value in values {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenTextGrowth.self, from: data)
            #expect(decoded == value)
        }

        // Verify hyphenated encoding
        let data = try encoder.encode(PenTextGrowth.fixedWidth)
        let json = String(data: data, encoding: .utf8)
        #expect(json == #""fixed-width""#)
    }

    @Test("PenAlignItems round-trips")
    func alignItems() throws {
        for value in [PenAlignItems.start, .center, .end] {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(PenAlignItems.self, from: data)
            #expect(decoded == value)
        }
    }

    // MARK: - PenFill

    @Test("PenFill decodes shorthand color string")
    func fillShorthand() throws {
        let json = Data(##""#FF0000""##.utf8)
        let decoded = try decoder.decode(PenFill.self, from: json)
        #expect(decoded == .shorthand("#FF0000"))
    }

    @Test("PenFill decodes shorthand variable")
    func fillShorthandVariable() throws {
        let json = Data(##""$color.primary""##.utf8)
        let decoded = try decoder.decode(PenFill.self, from: json)
        #expect(decoded == .shorthand("$color.primary"))
    }

    @Test("PenFill decodes color object")
    func fillColor() throws {
        let json = Data(##"{"type":"color","color":"#00FF00","blendMode":"multiply"}"##.utf8)
        let decoded = try decoder.decode(PenFill.self, from: json)
        if case let .color(fill) = decoded {
            #expect(fill.color == .literal("#00FF00"))
            #expect(fill.blendMode == .multiply)
        } else {
            Issue.record("Expected .color, got \(decoded)")
        }
    }

    @Test("PenFill decodes gradient")
    func fillGradient() throws {
        let json = Data("""
        {
            "type": "gradient",
            "gradientType": "linear",
            "rotation": 90,
            "colors": [
                {"color": "#FF0000", "position": 0},
                {"color": "#0000FF", "position": 1}
            ]
        }
        """.utf8)
        let decoded = try decoder.decode(PenFill.self, from: json)
        if case let .gradient(fill) = decoded {
            #expect(fill.gradientType == .linear)
            #expect(fill.rotation == .literal(90))
            #expect(fill.colors?.count == 2)
        } else {
            Issue.record("Expected .gradient, got \(decoded)")
        }
    }

    @Test("PenFill decodes image fill")
    func fillImage() throws {
        let json = Data(#"{"type":"image","url":"./logo.png","mode":"fill"}"#.utf8)
        let decoded = try decoder.decode(PenFill.self, from: json)
        if case let .image(fill) = decoded {
            #expect(fill.url == "./logo.png")
            #expect(fill.mode == .cover)
        } else {
            Issue.record("Expected .image, got \(decoded)")
        }
    }

    @Test("PenFills decodes single fill")
    func fillsSingle() throws {
        let json = Data(##""#FF0000""##.utf8)
        let decoded = try decoder.decode(PenFills.self, from: json)
        #expect(decoded.all.count == 1)
    }

    @Test("PenFills decodes array of fills")
    func fillsMultiple() throws {
        let json = Data(##"["#FF0000", {"type":"color","color":"#00FF00"}]"##.utf8)
        let decoded = try decoder.decode(PenFills.self, from: json)
        #expect(decoded.all.count == 2)
    }

    // MARK: - PenEffect

    @Test("PenEffect decodes shadow")
    func effectShadow() throws {
        let json = Data("""
        {
            "type": "shadow",
            "shadowType": "outer",
            "blur": 10,
            "offset": {"x": 2, "y": 4},
            "color": "#00000080"
        }
        """.utf8)
        let decoded = try decoder.decode(PenEffect.self, from: json)
        if case let .shadow(effect) = decoded {
            #expect(effect.shadowType == .outer)
            #expect(effect.blur == .literal(10))
            #expect(effect.color == .literal("#00000080"))
        } else {
            Issue.record("Expected .shadow, got \(decoded)")
        }
    }

    @Test("PenEffect decodes blur")
    func effectBlur() throws {
        let json = Data(#"{"type":"blur","radius":5}"#.utf8)
        let decoded = try decoder.decode(PenEffect.self, from: json)
        if case let .blur(effect) = decoded {
            #expect(effect.radius == .literal(5))
        } else {
            Issue.record("Expected .blur, got \(decoded)")
        }
    }

    @Test("PenEffects decodes single and array")
    func effectsSingleAndArray() throws {
        let single = Data(#"{"type":"blur","radius":5}"#.utf8)
        let decodedSingle = try decoder.decode(PenEffects.self, from: single)
        #expect(decodedSingle.all.count == 1)

        let array = Data(#"[{"type":"blur","radius":5},{"type":"shadow","blur":10}]"#.utf8)
        let decodedArray = try decoder.decode(PenEffects.self, from: array)
        #expect(decodedArray.all.count == 2)
    }

    // MARK: - PenStrokeWidth

    @Test("PenStrokeWidth decodes a uniform value")
    func strokeWidthUniform() throws {
        let decoded = try decoder.decode(PenStrokeWidth.self, from: Data("2".utf8))
        #expect(decoded == .uniform(.literal(2)))
    }

    @Test("PenStrokeWidth decodes a per-side object")
    func strokeWidthPerSide() throws {
        let json = Data("""
        {"top":1,"right":2,"bottom":3,"left":4}
        """.utf8)
        let decoded = try decoder.decode(PenStrokeWidth.self, from: json)
        if case let .perSide(sides) = decoded {
            #expect(sides.top == .literal(1))
            #expect(sides.right == .literal(2))
            #expect(sides.bottom == .literal(3))
            #expect(sides.left == .literal(4))
        } else {
            Issue.record("Expected per-side width")
        }
    }

    // MARK: - Text content

    @Test("Text content decodes a plain string")
    func textContentPlain() throws {
        let json = Data(#"{"type":"text","id":"t","content":"Hello World"}"#.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        guard case let .text(data) = node.kind else {
            Issue.record("Expected text kind")
            return
        }
        #expect(data.content == .literal("Hello World"))
    }

    @Test("Text content decodes a variable reference")
    func textContentVariable() throws {
        let json = Data(#"{"type":"text","id":"t","content":"$speaker.name"}"#.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        guard case let .text(data) = node.kind else {
            Issue.record("Expected text kind")
            return
        }
        #expect(data.content == .variable("speaker.name"))
    }

    /// 2.17 has no styled runs, so an array is malformed rather than rich text.
    /// A 2.8 – 2.10 file never reaches the decoder in this shape — ``PenLegacyMigrator``
    /// flattens the runs first.
    @Test("Text content rejects an array of styled runs")
    func textContentRejectsRuns() {
        let json = Data("""
        {"type":"text","id":"t","content":[{"content":"Hello ","fontWeight":"bold"}]}
        """.utf8)
        #expect(throws: (any Error).self) {
            try decoder.decode(PenNode.self, from: json)
        }
    }

    @Test("Text content round-trips a variable reference through encoding")
    func textContentRoundTrips() throws {
        let node = PenNode(
            id: "t",
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(content: .variable("headline")))
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try decoder.decode(PenNode.self, from: data)
        guard case let .text(decodedData) = decoded.kind else {
            Issue.record("Expected text kind")
            return
        }
        #expect(decodedData.content == .variable("headline"))
    }

    // MARK: - PenVariable

    @Test("PenVariable decodes simple color variable")
    func variableSimpleColor() throws {
        let json = Data(##"{"type":"color","value":"#FF0000"}"##.utf8)
        let decoded = try decoder.decode(PenVariable.self, from: json)
        #expect(decoded.type == .color)
        if case let .simple(value) = decoded.value {
            #expect(value == .string("#FF0000"))
        } else {
            Issue.record("Expected .simple")
        }
    }

    @Test("PenVariable decodes themed variable")
    func variableThemed() throws {
        let json = Data("""
        {
            "type": "color",
            "value": [
                {"value": "#FFFFFF", "theme": {"mode": "light"}},
                {"value": "#000000", "theme": {"mode": "dark"}}
            ]
        }
        """.utf8)
        let decoded = try decoder.decode(PenVariable.self, from: json)
        #expect(decoded.type == .color)
        if case let .themed(values) = decoded.value {
            #expect(values.count == 2)
            #expect(values[0].theme?["mode"] == "light")
            #expect(values[1].theme?["mode"] == "dark")
        } else {
            Issue.record("Expected .themed")
        }
    }

    // MARK: - PenCornerRadius

    @Test("PenCornerRadius decodes uniform value")
    func cornerRadiusUniform() throws {
        let json = Data("12".utf8)
        let decoded = try decoder.decode(PenCornerRadius.self, from: json)
        if case let .uniform(value) = decoded {
            #expect(value == .literal(12))
        } else {
            Issue.record("Expected .uniform")
        }
    }

    @Test("PenCornerRadius decodes per-corner array")
    func cornerRadiusPerCorner() throws {
        let json = Data("[4, 8, 12, 16]".utf8)
        let decoded = try decoder.decode(PenCornerRadius.self, from: json)
        if case let .perCorner(tl, tr, br, bl) = decoded {
            #expect(tl == .literal(4))
            #expect(tr == .literal(8))
            #expect(br == .literal(12))
            #expect(bl == .literal(16))
        } else {
            Issue.record("Expected .perCorner")
        }
    }

    @Test("PenCornerRadius round-trips uniform variable")
    func cornerRadiusVariableRoundTrip() throws {
        let original = PenCornerRadius.uniform(.variable("radius"))
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PenCornerRadius.self, from: data)
        #expect(decoded == original)
    }

    @Test("PenCornerRadius resolves uniform to Corners")
    func cornerRadiusResolve() {
        let radius = PenCornerRadius.uniform(.literal(8))
        let corners = radius.resolve()
        #expect(corners != nil)
        #expect(corners?.topLeft == 8)
        #expect(corners?.isUniform == true)
    }

    @Test("PenCornerRadius resolve returns nil for variable")
    func cornerRadiusResolveVariable() {
        let radius = PenCornerRadius.perCorner(
            topLeft: .literal(4), topRight: .variable("r"),
            bottomRight: .literal(12), bottomLeft: .literal(16)
        )
        #expect(radius.resolve() == nil)
    }

    // MARK: - PenDescendantOverride

    @Test("PenDescendantOverride decodes property patch")
    func descendantOverridePropertyPatch() throws {
        let json = Data(##"{"content": "Hello", "fontSize": 24}"##.utf8)
        let decoded = try decoder.decode(PenDescendantOverride.self, from: json)
        #expect(decoded.properties["content"] == .string("Hello"))
        #expect(decoded.properties["fontSize"] == .int(24))
        #expect(decoded.isObjectReplacement == false)
    }

    @Test("PenDescendantOverride detects object replacement")
    func descendantOverrideObjectReplacement() throws {
        let json = Data(##"{"type": "text", "id": "new1", "content": "Replaced"}"##.utf8)
        let decoded = try decoder.decode(PenDescendantOverride.self, from: json)
        #expect(decoded.isObjectReplacement == true)
        #expect(decoded.properties["type"] == .string("text"))
    }

    @Test("PenDescendantOverride round-trips")
    func descendantOverrideRoundTrip() throws {
        let original = PenDescendantOverride(properties: [
            "fill": .string("#FF0000"),
            "opacity": .double(0.5),
        ])
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PenDescendantOverride.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - PenNode (Frame)

    @Test("PenNode decodes frame with layout and children")
    func nodeFrame() throws {
        let json = Data(##"""
        {
            "id": "card",
            "type": "frame",
            "name": "Card",
            "width": 400,
            "height": "fit_content",
            "layout": "vertical",
            "gap": 16,
            "padding": 24,
            "fill": "#FFFFFF",
            "cornerRadius": 12,
            "children": [
                {
                    "id": "title",
                    "type": "text",
                    "content": "Hello",
                    "fontSize": 24
                }
            ]
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        #expect(node.id == "card")
        #expect(node.common.name == "Card")
        if case let .frame(data) = node.kind {
            #expect(data.width == .fixed(400))
            #expect(data.height == .fitContent(fallback: nil))
            #expect(data.layout == .vertical)
            #expect(data.gap == .literal(16))
            #expect(data.cornerRadius == .uniform(.literal(12)))
            #expect(data.children?.count == 1)
            if let child = data.children?.first, case let .text(textData) = child.kind {
                #expect(textData.content == .literal("Hello"))
                #expect(textData.fontSize == .literal(24))
            } else {
                Issue.record("Expected text child")
            }
        } else {
            Issue.record("Expected .frame kind")
        }
    }

    // MARK: - PenNode (Text)

    @Test("PenNode decodes text with style properties")
    func nodeText() throws {
        let json = Data(##"""
        {
            "id": "label",
            "type": "text",
            "content": "$title",
            "fontSize": 18,
            "fontWeight": "bold",
            "textAlign": "center",
            "fill": "#333333",
            "opacity": 0.9
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        #expect(node.id == "label")
        #expect(node.common.opacity == .literal(0.9))
        if case let .text(data) = node.kind {
            #expect(data.content == .variable("title"))
            #expect(data.fontSize == .literal(18))
            #expect(data.fontWeight == .literal("bold"))
            #expect(data.textAlign == .center)
        } else {
            Issue.record("Expected .text kind")
        }
    }

    // MARK: - PenNode (Rectangle)

    @Test("PenNode decodes rectangle with fills")
    func nodeRectangle() throws {
        let json = Data(##"""
        {
            "id": "bg",
            "type": "rectangle",
            "width": 200,
            "height": 100,
            "fill": {"type": "color", "color": "#FF0000"},
            "cornerRadius": [4, 4, 0, 0]
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        if case let .rectangle(data) = node.kind {
            #expect(data.width == .fixed(200))
            #expect(data.height == .fixed(100))
            if case let .perCorner(tl, tr, br, bl) = data.cornerRadius {
                #expect(tl == .literal(4))
                #expect(br == .literal(0))
                _ = (tr, bl) // suppress unused warnings
            } else {
                Issue.record("Expected .perCorner")
            }
        } else {
            Issue.record("Expected .rectangle kind")
        }
    }

    // MARK: - PenNode (Ref)

    @Test("PenNode decodes ref with descendant overrides")
    func nodeRef() throws {
        let json = Data(##"""
        {
            "id": "inst1",
            "type": "ref",
            "ref": "button-component",
            "descendants": {
                "label": {"content": "Click Me"},
                "icon": {"enabled": false}
            }
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        if case let .ref(data) = node.kind {
            #expect(data.ref == "button-component")
            #expect(data.descendants?.count == 2)
            #expect(data.descendants?["label"]?.properties["content"] == .string("Click Me"))
            #expect(data.descendants?["icon"]?.properties["enabled"] == .bool(false))
        } else {
            Issue.record("Expected .ref kind")
        }
    }

    // MARK: - PenNode (Unknown)

    @Test("PenNode preserves unknown node types")
    func nodeUnknown() throws {
        let json = Data(##"""
        {
            "id": "widget1",
            "type": "super_widget",
            "name": "My Widget",
            "customProp": "hello",
            "customNum": 42
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        #expect(node.id == "widget1")
        #expect(node.common.name == "My Widget")
        if case let .unknown(typeName, properties) = node.kind {
            #expect(typeName == "super_widget")
            #expect(properties["customProp"] == .string("hello"))
            #expect(properties["customNum"] == .int(42))
            // Reserved keys should NOT be in properties
            #expect(properties["id"] == nil)
            #expect(properties["type"] == nil)
            #expect(properties["name"] == nil)
        } else {
            Issue.record("Expected .unknown kind")
        }
    }

    // MARK: - PenNode common properties

    @Test("PenNode decodes common Entity properties alongside type-specific")
    func nodeCommonProperties() throws {
        let json = Data(##"""
        {
            "id": "shape1",
            "type": "ellipse",
            "name": "Circle",
            "x": 100,
            "y": 200,
            "rotation": 45,
            "opacity": 0.5,
            "enabled": false,
            "flipX": true,
            "reusable": true,
            "layoutPosition": "absolute",
            "width": 80,
            "height": 80
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        #expect(node.common.name == "Circle")
        #expect(node.common.x == .literal(100))
        #expect(node.common.y == .literal(200))
        #expect(node.common.rotation == .literal(45))
        #expect(node.common.opacity == .literal(0.5))
        #expect(node.common.enabled == .literal(false))
        #expect(node.common.flipX == .literal(true))
        #expect(node.common.reusable == true)
        #expect(node.common.layoutPosition == .absolute)
        if case let .ellipse(data) = node.kind {
            #expect(data.width == .fixed(80))
        } else {
            Issue.record("Expected .ellipse kind")
        }
    }

    // MARK: - PenNode round-trip

    @Test("PenNode frame round-trips through encode/decode")
    func nodeFrameRoundTrip() throws {
        let original = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame", opacity: .literal(0.8)),
            kind: .frame(PenNode.FrameData(
                width: .fixed(300),
                height: .fitContent(fallback: nil),
                layout: .horizontal,
                gap: .literal(8),
                children: [
                    PenNode(
                        id: "r1",
                        common: PenNodeCommon(),
                        kind: .rectangle(PenNode.RectangleData(
                            width: .fixed(50),
                            height: .fixed(50),
                            fills: .single(.shorthand("#FF0000"))
                        ))
                    ),
                ]
            ))
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PenNode.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - PenDocument

    @Test("PenDocument decodes full document")
    func documentDecode() throws {
        let json = Data(##"""
        {
            "version": "1.0",
            "themes": {
                "mode": ["light", "dark"]
            },
            "variables": {
                "primary": {
                    "type": "color",
                    "value": "#0066FF"
                }
            },
            "children": [
                {
                    "id": "root",
                    "type": "frame",
                    "width": 1920,
                    "height": 1080,
                    "layout": "vertical",
                    "children": [
                        {
                            "id": "heading",
                            "type": "text",
                            "content": "Title",
                            "fontSize": 48
                        }
                    ]
                }
            ]
        }
        """##.utf8)
        let doc = try decoder.decode(PenDocument.self, from: json)
        #expect(doc.version == "1.0")
        #expect(doc.themes?["mode"] == ["light", "dark"])
        #expect(doc.variables?["primary"]?.type == .color)
        #expect(doc.children.count == 1)
        #expect(doc.children[0].id == "root")
        if case let .frame(data) = doc.children[0].kind {
            #expect(data.children?.count == 1)
        } else {
            Issue.record("Expected .frame kind")
        }
    }

    @Test("PenDocument round-trips")
    func documentRoundTrip() throws {
        let original = PenDocument(
            version: "1.0",
            themes: ["mode": ["light", "dark"]],
            variables: [
                "bg": PenVariable(type: .color, value: .simple(.string("#FFFFFF"))),
            ],
            children: [
                PenNode(
                    id: "root",
                    common: PenNodeCommon(name: "Root"),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(1920),
                        height: .fixed(1080),
                        children: []
                    ))
                ),
            ]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PenDocument.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - PenNode (Group)

    @Test("PenNode decodes a group's children")
    func nodeGroup() throws {
        let json = Data(##"""
        {
            "id": "g1",
            "type": "group",
            "children": [
                {"id": "c1", "type": "rectangle", "width": 50, "height": 50},
                {"id": "c2", "type": "rectangle", "width": 50, "height": 50}
            ]
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        if case let .group(data) = node.kind {
            #expect(data.children?.count == 2)
        } else {
            Issue.record("Expected .group kind")
        }
    }

    @Test("PenNode decode ignores a group's legacy layout keys")
    func nodeGroupIgnoresLegacyLayoutKeys() throws {
        // A pre-2.17 group could carry layout/gap/alignItems (and width/height/padding/
        // justifyContent). GroupData no longer has these fields; a bare decode (bypassing
        // PenLegacyMigrator) simply ignores the unrecognized keys rather than failing.
        let json = Data(##"""
        {
            "id": "g1",
            "type": "group",
            "layout": "horizontal",
            "gap": 8,
            "alignItems": "center",
            "children": [
                {"id": "c1", "type": "rectangle", "width": 50, "height": 50}
            ]
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        if case let .group(data) = node.kind {
            #expect(data.children?.count == 1)
        } else {
            Issue.record("Expected .group kind")
        }
    }

    // MARK: - PenNode (Path)

    @Test("PenNode decodes path with geometry")
    func nodePath() throws {
        let json = Data(##"""
        {
            "id": "arrow",
            "type": "path",
            "width": 24,
            "height": 24,
            "geometry": "M12 2L22 12L12 22",
            "fillRule": "evenodd",
            "fill": "#000000"
        }
        """##.utf8)
        let node = try decoder.decode(PenNode.self, from: json)
        if case let .path(data) = node.kind {
            #expect(data.geometry == "M12 2L22 12L12 22")
            #expect(data.fillRule == .evenodd)
        } else {
            Issue.record("Expected .path kind")
        }
    }
}
