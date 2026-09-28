//
//  PenVariableResolverTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-03-22.
//

import Foundation
import Testing
import Woodcase

struct PenVariableResolverTests {
    // MARK: - Helpers

    /// Creates a minimal PenDocument with variables and a single node for testing.
    private func makeDocument(
        variables: [String: PenVariable] = [:],
        themes: [String: [String]]? = nil,
        children: [PenNode] = []
    ) -> PenDocument {
        PenDocument(
            version: "1",
            themes: themes,
            variables: variables.isEmpty ? nil : variables,
            children: children
        )
    }

    private func makeNode(
        id: String = "node1",
        common: PenNodeCommon = PenNodeCommon(),
        kind: PenNode.Kind
    ) -> PenNode {
        PenNode(id: id, common: common, kind: kind)
    }

    private func simpleVar(_ type: PenVariableType, _ value: AnyCodable) -> PenVariable {
        PenVariable(type: type, value: .simple(value))
    }

    // MARK: - Basic Resolution

    @Test("Resolves string variable to literal")
    func resolveStringVariable() {
        let doc = makeDocument(
            variables: ["headline": simpleVar(.string, "Breaking News")],
            children: [makeNode(
                kind: .text(PenNode.TextData(content: .variable("headline")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)

        if case let .text(data) = resolved.children[0].kind,
           let value = data.content
        {
            #expect(value == .literal("Breaking News"))
        } else {
            Issue.record("Expected resolved text content")
        }
    }

    @Test("Resolves number variable to literal")
    func resolveNumberVariable() {
        let doc = makeDocument(
            variables: ["spacing": simpleVar(.number, .double(16.0))],
            children: [makeNode(
                common: PenNodeCommon(x: .variable("spacing")),
                kind: .rectangle(PenNode.RectangleData())
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        #expect(resolved.children[0].common.x == .literal(16.0))
    }

    @Test("Resolves boolean variable to literal")
    func resolveBooleanVariable() {
        let doc = makeDocument(
            variables: ["showBorder": simpleVar(.boolean, .bool(true))],
            children: [makeNode(
                common: PenNodeCommon(enabled: .variable("showBorder")),
                kind: .rectangle(PenNode.RectangleData())
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        #expect(resolved.children[0].common.enabled == .literal(true))
    }

    @Test("Resolves color variable in fill")
    func resolveColorVariable() {
        let doc = makeDocument(
            variables: ["primaryColor": simpleVar(.color, "#FF6600")],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.color(PenFill.PenColorFill(color: .variable("primaryColor"))))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .color(colorFill) = fill
        {
            #expect(colorFill.color == .literal("#FF6600"))
        } else {
            Issue.record("Expected resolved color fill")
        }
    }

    // MARK: - Common Properties

    @Test("Resolves variables in common node properties")
    func resolveCommonProperties() {
        let doc = makeDocument(
            variables: [
                "posX": simpleVar(.number, .double(100)),
                "posY": simpleVar(.number, .double(200)),
                "alpha": simpleVar(.number, .double(0.8)),
            ],
            children: [makeNode(
                common: PenNodeCommon(
                    x: .variable("posX"),
                    y: .variable("posY"),
                    opacity: .variable("alpha")
                ),
                kind: .rectangle(PenNode.RectangleData())
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        let common = resolved.children[0].common
        #expect(common.x == .literal(100))
        #expect(common.y == .literal(200))
        #expect(common.opacity == .literal(0.8))
    }

    // MARK: - Padding

    @Test("Resolves uniform padding variable")
    func resolvePaddingUniform() {
        let doc = makeDocument(
            variables: ["pad": simpleVar(.number, .double(16))],
            children: [makeNode(
                kind: .frame(PenNode.FrameData(padding: .uniform(.variable("pad"))))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .frame(data) = resolved.children[0].kind,
           case let .uniform(value) = data.padding
        {
            #expect(value == .literal(16))
        } else {
            Issue.record("Expected resolved uniform padding")
        }
    }

    @Test("Resolves symmetric padding variables")
    func resolvePaddingSymmetric() {
        let doc = makeDocument(
            variables: [
                "padH": simpleVar(.number, .double(24)),
                "padV": simpleVar(.number, .double(12)),
            ],
            children: [makeNode(
                kind: .frame(PenNode.FrameData(
                    padding: .symmetric(h: .variable("padH"), v: .variable("padV"))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .frame(data) = resolved.children[0].kind,
           case let .symmetric(h, v) = data.padding
        {
            #expect(h == .literal(24))
            #expect(v == .literal(12))
        } else {
            Issue.record("Expected resolved symmetric padding")
        }
    }

    @Test("Resolves individual padding variables")
    func resolvePaddingIndividual() {
        let doc = makeDocument(
            variables: [
                "top": simpleVar(.number, .double(10)),
                "right": simpleVar(.number, .double(20)),
                "bottom": simpleVar(.number, .double(30)),
                "left": simpleVar(.number, .double(40)),
            ],
            children: [makeNode(
                kind: .frame(PenNode.FrameData(
                    padding: .individual(
                        top: .variable("top"),
                        right: .variable("right"),
                        bottom: .variable("bottom"),
                        left: .variable("left")
                    )
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .frame(data) = resolved.children[0].kind,
           case let .individual(top, right, bottom, left) = data.padding
        {
            #expect(top == .literal(10))
            #expect(right == .literal(20))
            #expect(bottom == .literal(30))
            #expect(left == .literal(40))
        } else {
            Issue.record("Expected resolved individual padding")
        }
    }

    // MARK: - Corner Radius

    @Test("Resolves uniform corner radius variable")
    func resolveCornerRadiusUniform() {
        let doc = makeDocument(
            variables: ["radius": simpleVar(.number, .double(8))],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    cornerRadius: .uniform(.variable("radius"))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .uniform(value) = data.cornerRadius
        {
            #expect(value == .literal(8))
        } else {
            Issue.record("Expected resolved uniform corner radius")
        }
    }

    @Test("Resolves per-corner corner radius variables")
    func resolveCornerRadiusPerCorner() {
        let doc = makeDocument(
            variables: [
                "tl": simpleVar(.number, .double(4)),
                "tr": simpleVar(.number, .double(8)),
                "br": simpleVar(.number, .double(12)),
                "bl": simpleVar(.number, .double(16)),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    cornerRadius: .perCorner(
                        topLeft: .variable("tl"),
                        topRight: .variable("tr"),
                        bottomRight: .variable("br"),
                        bottomLeft: .variable("bl")
                    )
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .perCorner(tl, tr, br, bl) = data.cornerRadius
        {
            #expect(tl == .literal(4))
            #expect(tr == .literal(8))
            #expect(br == .literal(12))
            #expect(bl == .literal(16))
        } else {
            Issue.record("Expected resolved per-corner radius")
        }
    }

    // MARK: - Sizing

    @Test("Resolves sizing variable to fixed")
    func resolveSizingVariable() {
        let doc = makeDocument(
            variables: ["width": simpleVar(.number, .double(300))],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(width: .variable("width")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind {
            #expect(data.width == .fixed(300))
        } else {
            Issue.record("Expected resolved sizing")
        }
    }

    // MARK: - Fills

    @Test("Resolves shorthand fill variable")
    func resolveFillShorthandVariable() {
        let doc = makeDocument(
            variables: ["primaryColor": simpleVar(.color, "#FF6600")],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.shorthand("$primaryColor"))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .shorthand(color) = fill
        {
            #expect(color == "#FF6600")
        } else {
            Issue.record("Expected resolved shorthand fill")
        }
    }

    @Test("Resolves gradient stop color and position variables")
    func resolveGradientStopVariables() {
        let doc = makeDocument(
            variables: [
                "startColor": simpleVar(.color, "#000000"),
                "stopPos": simpleVar(.number, .double(0.75)),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.gradient(PenFill.PenGradientFill(
                        colors: [
                            PenFill.PenGradientStop(
                                color: .variable("startColor"),
                                position: .literal(0)
                            ),
                            PenFill.PenGradientStop(
                                color: .literal("#FFFFFF"),
                                position: .variable("stopPos")
                            ),
                        ]
                    )))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .gradient(gradFill) = fill,
           let stops = gradFill.colors
        {
            #expect(stops[0].color == .literal("#000000"))
            #expect(stops[1].position == .literal(0.75))
        } else {
            Issue.record("Expected resolved gradient stops")
        }
    }

    // MARK: - Stroke

    @Test("Resolves uniform stroke width variable")
    func resolveStrokeWidthVariable() {
        let doc = makeDocument(
            variables: ["borderWidth": simpleVar(.number, .double(2))],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    strokeWidth: .uniform(.variable("borderWidth"))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .uniform(value) = data.strokeWidth
        {
            #expect(value == .literal(2))
        } else {
            Issue.record("Expected resolved stroke width")
        }
    }

    @Test("Resolves per-side stroke width variables")
    func resolveStrokePerSideVariable() {
        let doc = makeDocument(
            variables: [
                "topBorder": simpleVar(.number, .double(1)),
                "bottomBorder": simpleVar(.number, .double(3)),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    strokeWidth: .perSide(PenStrokeWidth.Sides(
                        top: .variable("topBorder"),
                        right: nil,
                        bottom: .variable("bottomBorder"),
                        left: nil
                    ))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .perSide(sides) = data.strokeWidth
        {
            #expect(sides.top == .literal(1))
            #expect(sides.right == nil)
            #expect(sides.bottom == .literal(3))
            #expect(sides.left == nil)
        } else {
            Issue.record("Expected resolved per-side stroke width")
        }
    }

    // MARK: - Effects

    @Test("Resolves shadow effect variables")
    func resolveEffectShadowVariables() {
        let doc = makeDocument(
            variables: [
                "shadowColor": simpleVar(.color, "#00000080"),
                "shadowBlur": simpleVar(.number, .double(10)),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    effects: .single(.shadow(PenEffect.PenShadowEffect(
                        blur: .variable("shadowBlur"),
                        color: .variable("shadowColor")
                    )))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(effect) = data.effects,
           case let .shadow(shadow) = effect
        {
            #expect(shadow.color == .literal("#00000080"))
            #expect(shadow.blur == .literal(10))
        } else {
            Issue.record("Expected resolved shadow effect")
        }
    }

    @Test("Resolves blur effect radius variable")
    func resolveEffectBlurVariable() {
        let doc = makeDocument(
            variables: ["blurAmount": simpleVar(.number, .double(5))],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    effects: .single(.blur(PenEffect.PenBlurEffect(
                        radius: .variable("blurAmount")
                    )))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(effect) = data.effects,
           case let .blur(blur) = effect
        {
            #expect(blur.radius == .literal(5))
        } else {
            Issue.record("Expected resolved blur effect")
        }
    }

    // MARK: - Text Content

    @Test("Resolves plain text content variable")
    func resolvePlainTextContentVariable() {
        let doc = makeDocument(
            variables: ["headline": simpleVar(.string, "Breaking News")],
            children: [makeNode(
                kind: .text(PenNode.TextData(content: .variable("headline")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .text(data) = resolved.children[0].kind,
           let value = data.content
        {
            #expect(value == .literal("Breaking News"))
        } else {
            Issue.record("Expected resolved text content")
        }
    }

    @Test("A \\$-escaped name decodes to a literal the resolver leaves untouched")
    func escapedDollarContentIsNotResolved() throws {
        // `v-muted` is a real, defined variable — without the escape this content
        // would resolve to "#888888" the way `resolvePlainTextContentVariable` does.
        let content = try JSONDecoder().decode(PenValue<String>.self, from: Data(##""\\$v-muted""##.utf8))
        let doc = makeDocument(
            variables: ["v-muted": simpleVar(.color, "#888888")],
            children: [makeNode(kind: .text(PenNode.TextData(content: content)))]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .text(data) = resolved.children[0].kind,
           let value = data.content
        {
            #expect(value == .literal("$v-muted"))
        } else {
            Issue.record("Expected literal text content")
        }
    }

    @Test("Resolves text node font variables")
    func resolveTextFontVariables() {
        let doc = makeDocument(
            variables: [
                "headingFont": simpleVar(.string, "Inter"),
                "headingSize": simpleVar(.number, .double(32)),
            ],
            children: [makeNode(
                kind: .text(PenNode.TextData(
                    content: .literal("Hello"),
                    fontFamily: .variable("headingFont"),
                    fontSize: .variable("headingSize")
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        guard case let .text(data) = resolved.children[0].kind else {
            Issue.record("Expected a text node")
            return
        }
        #expect(data.fontFamily == .literal("Inter"))
        #expect(data.fontSize == .literal(32))
    }

    // MARK: - Variable Chains

    @Test("Resolves variable chain (a -> b -> literal)")
    func resolveVariableChain() {
        let doc = makeDocument(
            variables: [
                "alias": simpleVar(.string, "$actual"),
                "actual": simpleVar(.string, "Resolved Value"),
            ],
            children: [makeNode(
                kind: .text(PenNode.TextData(content: .variable("alias")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .text(data) = resolved.children[0].kind,
           let value = data.content
        {
            #expect(value == .literal("Resolved Value"))
        } else {
            Issue.record("Expected resolved chain")
        }
    }

    @Test("Circular variable chain does not infinite loop")
    func resolveVariableChainDepthLimit() {
        let doc = makeDocument(
            variables: [
                "a": simpleVar(.string, "$b"),
                "b": simpleVar(.string, "$a"),
            ],
            children: [makeNode(
                kind: .text(PenNode.TextData(content: .variable("a")))
            )]
        )

        // Should not hang — leaves as variable since chain is unresolvable
        let resolved = PenVariableResolver.resolve(doc)
        if case let .text(data) = resolved.children[0].kind,
           let value = data.content
        {
            // The value should remain a variable since the chain is circular
            #expect(value.variableName != nil)
        } else {
            Issue.record("Expected unresolved variable")
        }
    }

    // MARK: - Themes

    @Test("Resolves themed variable with light mode")
    func resolveThemedVariableLightMode() {
        let doc = makeDocument(
            variables: [
                "bgColor": PenVariable(type: .color, value: .themed([
                    PenThemedValue(value: "#FFFFFF", theme: ["mode": "light"]),
                    PenThemedValue(value: "#1A1A1A", theme: ["mode": "dark"]),
                ])),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.color(PenFill.PenColorFill(color: .variable("bgColor"))))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc, theme: ["mode": "light"])
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .color(colorFill) = fill
        {
            #expect(colorFill.color == .literal("#FFFFFF"))
        } else {
            Issue.record("Expected resolved themed color (light)")
        }
    }

    @Test("Resolves themed variable with dark mode")
    func resolveThemedVariableDarkMode() {
        let doc = makeDocument(
            variables: [
                "bgColor": PenVariable(type: .color, value: .themed([
                    PenThemedValue(value: "#FFFFFF", theme: ["mode": "light"]),
                    PenThemedValue(value: "#1A1A1A", theme: ["mode": "dark"]),
                ])),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.color(PenFill.PenColorFill(color: .variable("bgColor"))))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc, theme: ["mode": "dark"])
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .color(colorFill) = fill
        {
            #expect(colorFill.color == .literal("#1A1A1A"))
        } else {
            Issue.record("Expected resolved themed color (dark)")
        }
    }

    @Test("Resolves themed variable with default fallback when no theme matches")
    func resolveThemedVariableDefaultFallback() {
        let doc = makeDocument(
            variables: [
                "bgColor": PenVariable(type: .color, value: .themed([
                    PenThemedValue(value: "#CCCCCC", theme: nil),
                    PenThemedValue(value: "#FFFFFF", theme: ["mode": "light"]),
                    PenThemedValue(value: "#1A1A1A", theme: ["mode": "dark"]),
                ])),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.color(PenFill.PenColorFill(color: .variable("bgColor"))))
                ))
            )]
        )

        // Empty theme — only the default (nil theme) matches
        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .color(colorFill) = fill
        {
            #expect(colorFill.color == .literal("#CCCCCC"))
        } else {
            Issue.record("Expected default themed color")
        }
    }

    @Test("Themed variable last match wins")
    func resolveThemedVariableLastMatchWins() {
        let doc = makeDocument(
            variables: [
                "fontSize": PenVariable(type: .number, value: .themed([
                    PenThemedValue(value: .double(14), theme: ["mode": "compact"]),
                    PenThemedValue(value: .double(18), theme: ["mode": "compact"]),
                ])),
            ],
            children: [makeNode(
                kind: .text(PenNode.TextData(fontSize: .variable("fontSize")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc, theme: ["mode": "compact"])
        if case let .text(data) = resolved.children[0].kind {
            #expect(data.fontSize == .literal(18))
        } else {
            Issue.record("Expected last-match-wins")
        }
    }

    @Test("Themed variable with multi-axis theme matching")
    func resolveThemedVariableMultiAxis() {
        let doc = makeDocument(
            variables: [
                "bgColor": PenVariable(type: .color, value: .themed([
                    PenThemedValue(value: "#FFFFFF", theme: ["mode": "light", "platform": "ios"]),
                    PenThemedValue(value: "#F0F0F0", theme: ["mode": "light", "platform": "web"]),
                    PenThemedValue(value: "#000000", theme: nil),
                ])),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.color(PenFill.PenColorFill(color: .variable("bgColor"))))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc, theme: ["mode": "light", "platform": "web"])
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .color(colorFill) = fill
        {
            #expect(colorFill.color == .literal("#F0F0F0"))
        } else {
            Issue.record("Expected multi-axis theme match")
        }
    }

    // MARK: - External Overrides

    @Test("External override takes precedence over document variable")
    func externalOverrideTakesPrecedence() {
        let doc = makeDocument(
            variables: ["headline": simpleVar(.string, "Original")],
            children: [makeNode(
                kind: .text(PenNode.TextData(content: .variable("headline")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc, overrides: ["headline": "Override Value"])
        if case let .text(data) = resolved.children[0].kind,
           let value = data.content
        {
            #expect(value == .literal("Override Value"))
        } else {
            Issue.record("Expected override value")
        }
    }

    @Test("External override for non-document variable resolves")
    func externalOverrideForNewVariable() {
        let doc = makeDocument(
            children: [makeNode(
                kind: .text(PenNode.TextData(content: .variable("externalVar")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc, overrides: ["externalVar": "External Value"])
        if case let .text(data) = resolved.children[0].kind,
           let value = data.content
        {
            #expect(value == .literal("External Value"))
        } else {
            Issue.record("Expected external variable value")
        }
    }

    // MARK: - Edge Cases

    @Test("Missing variable leaves PenValue unchanged")
    func missingVariableLeavesUnchanged() {
        let doc = makeDocument(
            children: [makeNode(
                common: PenNodeCommon(x: .variable("nonexistent")),
                kind: .rectangle(PenNode.RectangleData())
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        #expect(resolved.children[0].common.x == .variable("nonexistent"))
    }

    @Test("Type mismatch leaves PenValue unchanged")
    func typeMismatchLeavesUnchanged() {
        // Define a string variable but reference it where a Double is expected
        let doc = makeDocument(
            variables: ["myString": simpleVar(.string, "hello")],
            children: [makeNode(
                common: PenNodeCommon(x: .variable("myString")),
                kind: .rectangle(PenNode.RectangleData())
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        // x expects Double but variable is String — should remain .variable
        #expect(resolved.children[0].common.x == .variable("myString"))
    }

    @Test("Nested children are resolved recursively")
    func nestedChildrenResolvedRecursively() {
        let innerNode = makeNode(
            id: "inner",
            common: PenNodeCommon(opacity: .variable("alpha")),
            kind: .rectangle(PenNode.RectangleData())
        )
        let outerNode = makeNode(
            id: "outer",
            kind: .frame(PenNode.FrameData(children: [innerNode]))
        )
        let doc = makeDocument(
            variables: ["alpha": simpleVar(.number, .double(0.5))],
            children: [outerNode]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .frame(data) = resolved.children[0].kind,
           let child = data.children?.first
        {
            #expect(child.common.opacity == .literal(0.5))
        } else {
            Issue.record("Expected recursively resolved child")
        }
    }

    @Test("Document with no variables returns unchanged")
    func documentWithNoVariablesReturnsUnchanged() {
        let doc = makeDocument(
            children: [makeNode(
                common: PenNodeCommon(x: .literal(100)),
                kind: .rectangle(PenNode.RectangleData())
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        #expect(resolved.children[0].common.x == .literal(100))
    }

    @Test("Int variable resolves as Double for PenValue<Double>")
    func resolveIntAsDouble() {
        let doc = makeDocument(
            variables: ["size": simpleVar(.number, .int(16))],
            children: [makeNode(
                kind: .text(PenNode.TextData(fontSize: .variable("size")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .text(data) = resolved.children[0].kind {
            #expect(data.fontSize == .literal(16))
        } else {
            Issue.record("Expected int-as-double resolution")
        }
    }

    @Test("Resolves mesh gradient color variables")
    func resolveMeshGradientColorVariables() {
        let doc = makeDocument(
            variables: ["meshColor": simpleVar(.color, "#FF0000")],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.meshGradient(PenFill.PenMeshGradientFill(
                        colors: [.variable("meshColor"), .literal("#00FF00")]
                    )))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .meshGradient(mesh) = fill,
           let colors = mesh.colors
        {
            #expect(colors[0] == .literal("#FF0000"))
            #expect(colors[1] == .literal("#00FF00"))
        } else {
            Issue.record("Expected resolved mesh gradient colors")
        }
    }

    @Test("Resolves text node font properties")
    func resolveTextFontProperties() {
        let doc = makeDocument(
            variables: [
                "fontFam": simpleVar(.string, "Inter"),
                "fontSz": simpleVar(.number, .double(24)),
                "fontWt": simpleVar(.string, "bold"),
            ],
            children: [makeNode(
                kind: .text(PenNode.TextData(
                    fontFamily: .variable("fontFam"),
                    fontSize: .variable("fontSz"),
                    fontWeight: .variable("fontWt")
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .text(data) = resolved.children[0].kind {
            #expect(data.fontFamily == .literal("Inter"))
            #expect(data.fontSize == .literal(24))
            #expect(data.fontWeight == .literal("bold"))
        } else {
            Issue.record("Expected resolved text font properties")
        }
    }

    @Test("Resolves frame gap and clip variables")
    func resolveFrameGapAndClip() {
        let doc = makeDocument(
            variables: [
                "gapSize": simpleVar(.number, .double(8)),
                "shouldClip": simpleVar(.boolean, .bool(true)),
            ],
            children: [makeNode(
                kind: .frame(PenNode.FrameData(
                    clip: .variable("shouldClip"),
                    gap: .variable("gapSize")
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .frame(data) = resolved.children[0].kind {
            #expect(data.clip == .literal(true))
            #expect(data.gap == .literal(8))
        } else {
            Issue.record("Expected resolved frame properties")
        }
    }

    @Test("Resolves ellipse-specific variables")
    func resolveEllipseVariables() {
        let doc = makeDocument(
            variables: [
                "inner": simpleVar(.number, .double(0.5)),
                "sweep": simpleVar(.number, .double(270)),
            ],
            children: [makeNode(
                kind: .ellipse(PenNode.EllipseData(
                    innerRadius: .variable("inner"),
                    sweepAngle: .variable("sweep")
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .ellipse(data) = resolved.children[0].kind {
            #expect(data.innerRadius == .literal(0.5))
            #expect(data.sweepAngle == .literal(270))
        } else {
            Issue.record("Expected resolved ellipse properties")
        }
    }

    @Test("Resolves polygon count variable")
    func resolvePolygonCountVariable() {
        let doc = makeDocument(
            variables: ["sides": simpleVar(.number, .double(6))],
            children: [makeNode(
                kind: .polygon(PenNode.PolygonData(polygonCount: .variable("sides")))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .polygon(data) = resolved.children[0].kind {
            #expect(data.polygonCount == .literal(6))
        } else {
            Issue.record("Expected resolved polygon count")
        }
    }

    @Test("Resolves stroke paint variables")
    func resolveStrokePaint() {
        let doc = makeDocument(
            variables: ["strokeColor": simpleVar(.color, "#333333")],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    stroke: .single(.color(PenFill.PenColorFill(color: .variable("strokeColor"))))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind {
            if case let .single(fill) = data.stroke,
               case let .color(colorFill) = fill
            {
                #expect(colorFill.color == .literal("#333333"))
            } else {
                Issue.record("Expected resolved stroke fill")
            }
        } else {
            Issue.record("Expected resolved stroke")
        }
    }

    @Test("Resolves shadow offset variables")
    func resolveShadowOffsetVariables() {
        let doc = makeDocument(
            variables: [
                "offsetX": simpleVar(.number, .double(2)),
                "offsetY": simpleVar(.number, .double(4)),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    effects: .single(.shadow(PenEffect.PenShadowEffect(
                        offset: PenEffect.PenOffset(
                            x: .variable("offsetX"),
                            y: .variable("offsetY")
                        )
                    )))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(effect) = data.effects,
           case let .shadow(shadow) = effect,
           let offset = shadow.offset
        {
            #expect(offset.x == .literal(2))
            #expect(offset.y == .literal(4))
        } else {
            Issue.record("Expected resolved shadow offsets")
        }
    }

    @Test("Preserves variables dict on resolved document")
    func preservesVariablesDict() {
        let doc = makeDocument(
            variables: ["x": simpleVar(.number, .double(10))],
            children: []
        )

        let resolved = PenVariableResolver.resolve(doc)
        #expect(resolved.variables != nil)
        #expect(resolved.variables?["x"] != nil)
    }

    @Test("Resolves group effect variables")
    func resolveGroupDataVariables() {
        // A group's only remaining resolvable surface is its effects — layout
        // properties (gap, padding, ...) no longer exist on GroupData.
        let doc = makeDocument(
            variables: [
                "offsetX": simpleVar(.number, .double(2)),
                "offsetY": simpleVar(.number, .double(4)),
            ],
            children: [makeNode(
                kind: .group(PenNode.GroupData(
                    effects: .single(.shadow(PenEffect.PenShadowEffect(
                        offset: PenEffect.PenOffset(
                            x: .variable("offsetX"),
                            y: .variable("offsetY")
                        )
                    )))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .group(data) = resolved.children[0].kind,
           case let .single(effect) = data.effects,
           case let .shadow(shadow) = effect,
           let offset = shadow.offset
        {
            #expect(offset.x == .literal(2))
            #expect(offset.y == .literal(4))
        } else {
            Issue.record("Expected resolved group effect offsets")
        }
    }

    @Test("Resolves icon variables")
    func resolveIconVariables() {
        let doc = makeDocument(
            variables: [
                "iconName": simpleVar(.string, "arrow-right"),
                "iconWeight": simpleVar(.number, .double(400)),
            ],
            children: [makeNode(
                kind: .icon(PenNode.IconData(
                    icon: .variable("iconName"),
                    weight: .variable("iconWeight")
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .icon(data) = resolved.children[0].kind {
            #expect(data.icon == .literal("arrow-right"))
            #expect(data.weight == .literal(400))
        } else {
            Issue.record("Expected resolved icon")
        }
    }

    @Test("Resolves icon width and height variables")
    func resolveIconSizingVariables() {
        let doc = makeDocument(
            variables: [
                "iconW": simpleVar(.number, .double(24)),
                "iconH": simpleVar(.number, .double(24)),
            ],
            children: [makeNode(
                kind: .icon(PenNode.IconData(
                    icon: .literal("bell"),
                    library: .literal("lucide"),
                    width: .variable("iconW"),
                    height: .variable("iconH")
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .icon(data) = resolved.children[0].kind {
            #expect(data.width == .fixed(24))
            #expect(data.height == .fixed(24))
            #expect(data.icon == .literal("bell"))
            #expect(data.library == .literal("lucide"))
        } else {
            Issue.record("Expected resolved icon with sizing")
        }
    }

    @Test("Resolves gradient fill size variables")
    func resolveGradientFillSizeVariables() {
        let doc = makeDocument(
            variables: ["sizeW": simpleVar(.number, .double(100))],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.gradient(PenFill.PenGradientFill(
                        size: PenFill.PenFillSize(
                            width: .variable("sizeW"),
                            height: .literal(200)
                        )
                    )))
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .single(fill) = data.fills,
           case let .gradient(grad) = fill
        {
            #expect(grad.size?.width == .literal(100))
            #expect(grad.size?.height == .literal(200))
        } else {
            Issue.record("Expected resolved gradient fill size")
        }
    }

    @Test("Resolves multiple fills in array")
    func resolveMultipleFills() {
        let doc = makeDocument(
            variables: [
                "color1": simpleVar(.color, "#FF0000"),
                "color2": simpleVar(.color, "#00FF00"),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    fills: .multiple([
                        .color(PenFill.PenColorFill(color: .variable("color1"))),
                        .color(PenFill.PenColorFill(color: .variable("color2"))),
                    ])
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .multiple(fills) = data.fills
        {
            if case let .color(c1) = fills[0] { #expect(c1.color == .literal("#FF0000")) }
            if case let .color(c2) = fills[1] { #expect(c2.color == .literal("#00FF00")) }
        } else {
            Issue.record("Expected resolved multiple fills")
        }
    }

    @Test("Resolves multiple effects in array")
    func resolveMultipleEffects() {
        let doc = makeDocument(
            variables: [
                "blur1": simpleVar(.number, .double(5)),
                "blur2": simpleVar(.number, .double(10)),
            ],
            children: [makeNode(
                kind: .rectangle(PenNode.RectangleData(
                    effects: .multiple([
                        .blur(PenEffect.PenBlurEffect(radius: .variable("blur1"))),
                        .blur(PenEffect.PenBlurEffect(radius: .variable("blur2"))),
                    ])
                ))
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        if case let .rectangle(data) = resolved.children[0].kind,
           case let .multiple(effects) = data.effects
        {
            if case let .blur(b1) = effects[0] { #expect(b1.radius == .literal(5)) }
            if case let .blur(b2) = effects[1] { #expect(b2.radius == .literal(10)) }
        } else {
            Issue.record("Expected resolved multiple effects")
        }
    }

    @Test("Literal values pass through unchanged")
    func literalValuesPassThrough() {
        let doc = makeDocument(
            variables: ["unused": simpleVar(.number, .double(99))],
            children: [makeNode(
                common: PenNodeCommon(x: .literal(42), y: .literal(84)),
                kind: .rectangle(PenNode.RectangleData())
            )]
        )

        let resolved = PenVariableResolver.resolve(doc)
        #expect(resolved.children[0].common.x == .literal(42))
        #expect(resolved.children[0].common.y == .literal(84))
    }
}
