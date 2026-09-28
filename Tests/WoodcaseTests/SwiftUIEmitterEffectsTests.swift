//
//  SwiftUIEmitterEffectsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a node's effects, transforms and blend mode become in emitted SwiftUI, over
/// small synthetic documents. ``SwiftUIRenderTests`` measures the same decisions against
/// Pen's exports of `render-transforms-and-effects`, `render-shadows` and
/// `render-background-blur`.
struct SwiftUIEmitterEffectsTests {
    // MARK: - Shadows

    @Test("An outer shadow is cast by the shape's silhouette at half Pen's blur")
    func outerShadow() throws {
        let effect = ##"{"type": "shadow", "shadowType": "outer", "color": "#00000080", "offset": {"x": 4, "y": 6}, "blur": 8}"##
        let code = try body(child: rect(##""cornerRadius": 8, "effect": \##(effect)"##))
        #expect(code.contains(
            ".penDropShadow(RoundedRectangle(cornerRadius: 8, style: .circular), color: Color(hex: 0x000000, opacity: 0.502), radius: 4, x: 4, y: 6)"
        ))
    }

    @Test("A shadow with no type is an outer shadow, with no offset written when it has none")
    func defaultShadow() throws {
        let code = try body(child: rect(##""effect": {"type": "shadow", "color": "#FF0000", "blur": 6}"##))
        #expect(code.contains(".penDropShadow(Rectangle(), color: Color(hex: 0xFF0000), radius: 3)"))
    }

    @Test("Several outer shadows are drawn in array order: the first is the lowest background")
    func shadowOrder() throws {
        let effects = ##"[{"type": "shadow", "color": "#FF0000", "blur": 2}, {"type": "shadow", "color": "#0000FF", "blur": 4}]"##
        let code = try body(child: rect(##""effect": \##(effects)"##))
        let red = try #require(code.range(of: "color: Color(hex: 0xFF0000), radius: 1"))
        let blue = try #require(code.range(of: "color: Color(hex: 0x0000FF), radius: 2"))
        #expect(blue.lowerBound < red.lowerBound)
    }

    @Test("A shadow's own blend mode is passed along")
    func shadowBlendMode() throws {
        let code = try body(child: rect(##""effect": {"type": "shadow", "color": "#FF0000", "blur": 2, "blendMode": "multiply"}"##))
        #expect(code.contains("radius: 1, blendMode: .multiply)"))
    }

    @Test("A disabled shadow is not drawn; an enabled one beside it is")
    func disabledShadow() throws {
        let effects = ##"[{"type": "shadow", "enabled": false, "color": "#FF0000", "blur": 2}, {"type": "shadow", "color": "#0000FF", "blur": 2}]"##
        let code = try body(child: rect(##""effect": \##(effects)"##))
        #expect(code.contains("color: Color(hex: 0x0000FF), radius: 1)"))
        #expect(!code.contains("0xFF0000), radius"))
    }

    @Test("An inner shadow on a shape is an overlay in the shape")
    func innerShadowOnShape() throws {
        let effect = ##"{"type": "shadow", "shadowType": "inner", "color": "#00AA00", "offset": {"x": 6, "y": 6}, "blur": 10}"##
        let code = try body(child: ##"{"type": "ellipse", "id": "e", "width": 30, "height": 30, "fill": "#DDEEFF", "effect": \##(effect)}"##)
        #expect(code.contains(".penInnerShadow(Ellipse(), color: Color(hex: 0x00AA00), radius: 5, x: 6, y: 6)"))
    }

    /// A ring's hole is a second subpath: clipped with the non-zero rule the hole is inside
    /// the shape and fills black (`render-inner-shadow-shapes-donut` measured 19.898).
    @Test("An inner shadow on an even-odd shape clips even-odd")
    func innerShadowOnRing() throws {
        let effect = ##"{"type": "shadow", "shadowType": "inner", "color": "#00AA00", "offset": {"x": 6, "y": 6}, "blur": 10}"##
        let code = try body(child: ##"{"type": "ellipse", "id": "e", "width": 30, "height": 30, "innerRadius": 0.5, "fill": "#DDEEFF", "effect": \##(effect)}"##)
        #expect(code.contains("radius: 5, x: 6, y: 6, eoFill: true)"), "\(code)")
    }

    @Test("A frame's inner shadow sits over its fills and under its children")
    func innerShadowUnderChildren() throws {
        let effect = ##"{"type": "shadow", "shadowType": "inner", "color": "#000000", "blur": 24}"##
        let frame = ##"{"type": "frame", "id": "f", "width": 100, "height": 100, "fill": "#FFFFFF", "effect": \##(effect), "children": [\##(rect(""))]}"##
        let code = try body(child: frame)
        let shadow = try #require(code.range(of: "PenInnerShadow(Rectangle(), color: Color(hex: 0x000000), radius: 12)"))
        let fill = try #require(code.range(of: ".background(Color(hex: 0xFFFFFF))"))
        #expect(shadow.lowerBound < fill.lowerBound)
        #expect(code.contains(".background {"))
    }

    @Test("Text casts its glyphs' shadow, and its inner shadow falls inside its glyphs, with no warning")
    func textShadows() throws {
        let effects = ##"[{"type": "shadow", "color": "#000000", "blur": 4, "offset": {"x": 1, "y": 2}}, {"type": "shadow", "shadowType": "inner", "color": "#000000", "blur": 4}]"##
        let diagnostics = PenDiagnosticCollector()
        let code = try body(
            child: ##"{"type": "text", "id": "t", "content": "Hi", "fill": "#FF0000", "effect": \##(effects)}"##, diagnostics: diagnostics
        )
        #expect(code.contains(".shadow(color: Color(hex: 0x000000), radius: 2, x: 1, y: 2)"))
        #expect(code.contains(".penTextFill(innerShadows: [PenShadowStyle(color: Color(hex: 0x000000), radius: 2)]) {"))
        // The glyphs cast the shadow unpainted, so the colour is a layer, not a foreground style.
        #expect(!code.contains(".foregroundStyle(Color(hex: 0xFF0000))"))
        #expect(code.contains("Color(hex: 0xFF0000)"))
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "t" })
    }

    @Test("Text's inner shadows keep their order, offset and blend mode")
    func textInnerShadowArguments() throws {
        let effects = ##"[{"type": "shadow", "shadowType": "inner", "color": "#FF0000", "blur": 2, "offset": {"x": 3, "y": 4}}, {"type": "shadow", "shadowType": "inner", "color": "#0000FF", "blur": 6, "blendMode": "multiply"}]"##
        let code = try body(child: ##"{"type": "text", "id": "t", "content": "Hi", "fill": "#00FF00", "effect": \##(effects)}"##)
        #expect(code.contains(
            "[PenShadowStyle(color: Color(hex: 0xFF0000), radius: 1, x: 3, y: 4), PenShadowStyle(color: Color(hex: 0x0000FF), radius: 3, blendMode: .multiply)]"
        ))
    }

    @Test("An unfilled text still shows its inner shadow: the glyphs cast it, not the paint")
    func unfilledTextInnerShadow() throws {
        let effect = ##"{"type": "shadow", "shadowType": "inner", "color": "#000000", "blur": 4}"##
        let code = try body(child: ##"{"type": "text", "id": "t", "content": "Hi", "effect": \##(effect)}"##)
        #expect(code.contains(".penTextFill(innerShadows: [PenShadowStyle(color: Color(hex: 0x000000), radius: 2)]) {"))
        #expect(code.contains("Color.clear"))
        #expect(!code.contains(".foregroundStyle(.clear)"))
    }

    /// Themed colours are read through `PenTheme` now (SwiftUIEmitterThemeReadTests); only a
    /// variable the document does not define is left out, and it is named.
    @Test("A shadow whose colour is a variable the document lacks is a warning, and is not drawn")
    func shadowVariable() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(child: rect(##""effect": {"type": "shadow", "color": "$shade", "blur": 4}"##), diagnostics: diagnostics)
        #expect(!code.contains("penDropShadow"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the colour variable $shade") })
    }

    /// Effect numbers are read through `PenTheme` now (SwiftUIEmitterThemeReadTests); only a
    /// variable the document does not define is left out, and it is named.
    @Test("A shadow's blur or offset naming a variable the document lacks is reported, and no shadow is drawn")
    func shadowBlurAndOffsetVariableUndefined() throws {
        let blur = PenDiagnosticCollector()
        let blurCode = try body(child: rect(##""effect": {"type": "shadow", "color": "#FF0000", "blur": "$missingBlur"}"##), diagnostics: blur)
        #expect(!blurCode.contains("penDropShadow"))
        #expect(blur.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the number variable $missingBlur") })

        let offset = PenDiagnosticCollector()
        let offsetCode = try body(
            child: rect(##""effect": {"type": "shadow", "color": "#FF0000", "blur": 4, "offset": {"x": "$missingOffset", "y": 2}}"##),
            diagnostics: offset
        )
        #expect(!offsetCode.contains("penDropShadow"))
        #expect(offset.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the number variable $missingOffset") })
    }

    // MARK: - Blur

    @Test("A layer blur is SwiftUI's blur at half Pen's radius")
    func layerBlur() throws {
        let code = try body(child: rect(##""effect": {"type": "blur", "radius": 8}"##))
        #expect(code.contains(".blur(radius: 4)"))
    }

    @Test("A background blur is a Material in the node's shape, and a warning that it is approximate")
    func backgroundBlur() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(
            child: ##"{"type": "rectangle", "id": "r", "width": 10, "height": 10, "cornerRadius": 24, "fill": "#FFFFFF33", "effect": {"type": "background_blur", "radius": 8}}"##,
            diagnostics: diagnostics
        )
        #expect(code.contains(".penBackgroundBlur(RoundedRectangle(cornerRadius: 24, style: .circular), radius: 8)"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("background blur") })
    }

    @Test("A layer or background blur naming a variable the document lacks is reported, and no blur is drawn")
    func blurRadiusVariableUndefined() throws {
        let layer = PenDiagnosticCollector()
        let layerCode = try body(child: rect(##""effect": {"type": "blur", "radius": "$missingRadius"}"##), diagnostics: layer)
        #expect(!layerCode.contains(".blur("))
        #expect(layer.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the number variable $missingRadius") })

        let background = PenDiagnosticCollector()
        let backgroundCode = try body(
            child: ##"{"type": "rectangle", "id": "r", "width": 10, "height": 10, "fill": "#FFFFFF33", "effect": {"type": "background_blur", "radius": "$missingRadius"}}"##,
            diagnostics: background
        )
        #expect(!backgroundCode.contains("penBackgroundBlur"))
        #expect(background.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the number variable $missingRadius") })
    }

    @Test("A background blur through no visible fill draws nothing, as in Pen")
    func backgroundBlurWithoutFill() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(
            child: ##"{"type": "rectangle", "id": "r", "width": 10, "height": 10, "fill": "#FFFFFF00", "effect": {"type": "background_blur", "radius": 8}}"##,
            diagnostics: diagnostics
        )
        #expect(!code.contains("penBackgroundBlur"))
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "r" })
    }

    // MARK: - Transforms

    @Test("A rotated node turns counter-clockwise inside a frame of its rotated bounding box")
    func rotation() throws {
        let code = try body(child: ##"{"type": "rectangle", "id": "r", "width": 80, "height": 40, "rotation": 90, "fill": "#FF0000"}"##)
        #expect(code.contains(".frame(width: 80, height: 40)\n"))
        #expect(code.contains(".rotationEffect(.degrees(-90))"))
        #expect(code.contains(".frame(width: 40, height: 80)"))
    }

    @Test("A rotation's bounding box is Pen's layout's, rounded to a millionth of a point")
    func rotationBoundingBox() throws {
        let code = try body(child: ##"{"type": "rectangle", "id": "r", "width": 80, "height": 80, "rotation": 45, "fill": "#FF0000"}"##)
        #expect(code.contains(".frame(width: 113.137085, height: 113.137085)"))
    }

    @Test("Flips are a negative scale, applied before the rotation, and draw no warning")
    func flips() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(
            child: ##"{"type": "rectangle", "id": "r", "width": 10, "height": 10, "flipX": true, "flipY": true, "rotation": 30, "fill": "#FF0000"}"##,
            diagnostics: diagnostics
        )
        let flip = try #require(code.range(of: ".scaleEffect(x: -1, y: -1)"))
        let turn = try #require(code.range(of: ".rotationEffect(.degrees(-30))"))
        #expect(flip.lowerBound < turn.lowerBound)
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "r" })
    }

    @Test("Effects turn with the node: they come before the transform")
    func effectsBeforeTransform() throws {
        let code = try body(child: rect(##""rotation": 10, "effect": {"type": "blur", "radius": 2}"##))
        let blur = try #require(code.range(of: ".blur(radius: 1)"))
        let turn = try #require(code.range(of: ".rotationEffect"))
        #expect(blur.lowerBound < turn.lowerBound)
    }

    // MARK: - Blend modes

    @Test("A node blend mode is the outermost modifier, after opacity")
    func nodeBlendMode() throws {
        let code = try body(child: rect(##""opacity": 0.5, "blendMode": "multiply""##))
        let opacity = try #require(code.range(of: ".opacity(0.5)"))
        let blend = try #require(code.range(of: ".blendMode(.multiply)"))
        #expect(opacity.lowerBound < blend.lowerBound)
    }

    @Test("linearBurn and linearDodge are exactly plusDarker and plusLighter; light is lighten", arguments: [
        ("linearBurn", "plusDarker"), ("linearDodge", "plusLighter"), ("light", "lighten"), ("colorDodge", "colorDodge"),
    ])
    func blendModeNames(pen: String, swiftUI: String) throws {
        let code = try body(child: rect(##""blendMode": "\##(pen)""##))
        #expect(code.contains(".blendMode(.\(swiftUI))"))
    }

    @Test("A frame's and a text's blend mode are emitted, with no warning")
    func blendModeOnFrameAndText() throws {
        let diagnostics = PenDiagnosticCollector()
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "blendMode": "screen"}"##
        let frame = ##"{"type": "frame", "id": "f", "blendMode": "overlay", "children": [\##(text)]}"##
        let code = try body(child: frame, diagnostics: diagnostics)
        #expect(code.contains(".blendMode(.screen)"))
        #expect(code.contains(".blendMode(.overlay)"))
        #expect(diagnostics.diagnostics.isEmpty)
    }

    // MARK: - Fixtures

    /// Regenerate with `UPDATE_GOLDEN=1 swift test --filter SwiftUIEmitterEffectsTests`, then read the diff.
    @Test("Each effects fixture's pages match their golden", arguments: [
        "render-transforms-and-effects", "render-shadows", "render-background-blur", "render-group-shadows",
        "render-stroke-shadows", "render-sizeless-frames",
    ])
    func fixtureMatchesGolden(fixture: String) throws {
        let pages = try SwiftUIFixtures.emit(fixture).files
            .filter { $0.path.contains("/Pages/") }
            .sorted { $0.path < $1.path }
        #expect(!pages.isEmpty)
        try GoldenFile.assert(pages.map(\.content).joined(separator: "\n"), name: "\(fixture).swift", subdirectory: "swiftui")
    }

    // MARK: - Helpers

    private func rect(_ keys: String) -> String {
        let extra = keys.isEmpty ? "" : ", \(keys)"
        return ##"{"type": "rectangle", "id": "r", "width": 10, "height": 10, "fill": "#FF0000"\##(extra)}"##
    }

    /// Emit a 2.19 document whose root frame holds `child`, and return the page's source.
    private func body(child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
