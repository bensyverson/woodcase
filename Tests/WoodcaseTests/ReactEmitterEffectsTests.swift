//
//  ReactEmitterEffectsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter writes a node's effects the way Pen draws them: outer shadows and
/// layer blur on every kind of node, shadows stacked in Pen's order, blur radii kept whole,
/// and no background blur through a node Pen would not blur (leaf `0M8jRo`).
struct ReactEmitterEffectsTests {
    // MARK: - Helpers

    /// The emitted `Card` component, whose one child is `child` (a JSON object).
    private func card(_ child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document),
            diagnostics: diagnostics
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    /// Two outer shadows: a soft black one first (bottom), a red one second (top).
    private static let twoShadows = """
    [{"type": "shadow", "shadowType": "outer", "color": "#00000080", "offset": {"x": 0, "y": 4}, "blur": 8},
     {"type": "shadow", "shadowType": "outer", "color": "#FF0000", "offset": {"x": 2, "y": 2}, "blur": 3}]
    """

    // MARK: - Every node kind (criterion a)

    @Test("Text casts its outer shadows from its glyphs: text-shadow, top shadow first")
    func textShadow() throws {
        let content = try card(##"{"type": "text", "id": "T1", "name": "Label", "content": "Hi", "fill": "#000000", "effect": \##(Self.twoShadows)}"##)
        #expect(content.contains(##"textShadow: "2px 2px 3px #FF0000, 0px 4px 8px #00000080","##))
        #expect(!content.contains("boxShadow"))
    }

    @Test("Painted text casts its shadows through a filter, since text-shadow would draw over the clipped paint")
    func paintedTextShadow() throws {
        let fill = ##"{"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}"##
        let content = try card(##"{"type": "text", "id": "T1", "name": "Label", "content": "Hi", "fill": \##(fill), "effect": \##(Self.twoShadows)}"##)
        #expect(content.contains(##"filter: "drop-shadow(2px 2px 1.5px #FF0000) drop-shadow(0px 4px 4px #00000080)","##))
        #expect(!content.contains("textShadow"))
    }

    @Test("A text's layer blur is a filter")
    func textBlur() throws {
        let content = try card(##"{"type": "text", "id": "T1", "name": "Label", "content": "Hi", "effect": {"type": "blur", "radius": 4}}"##)
        #expect(content.contains(##"filter: "blur(2px)","##))
    }

    @Test("An icon casts its outer shadows through a drop-shadow filter")
    func iconShadow() throws {
        let content = try card(##"{"type": "icon", "id": "I1", "name": "Star", "library": "lucide", "icon": "star", "width": 24, "height": 24, "effect": \##(Self.twoShadows)}"##)
        #expect(content.contains(##"filter: "drop-shadow(2px 2px 1.5px #FF0000) drop-shadow(0px 4px 4px #00000080)","##))
    }

    @Test("A path casts its outer shadows through a drop-shadow filter on its svg")
    func pathShadow() throws {
        let content = try card(##"{"type": "path", "id": "P1", "name": "Wedge", "width": 60, "height": 60, "geometry": "M0 60 L30 0 L60 60 Z", "fill": "#AA00AA", "effect": \##(Self.twoShadows)}"##)
        #expect(content.contains(##"filter: "drop-shadow(2px 2px 1.5px #FF0000) drop-shadow(0px 4px 4px #00000080)","##))
    }

    @Test("A polygon casts its outer shadow")
    func polygonShadow() throws {
        let content = try card(##"{"type": "polygon", "id": "P1", "name": "Hex", "width": 60, "height": 60, "polygonCount": 6, "fill": "#335577", "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 1, "y": 2}, "blur": 4}}"##)
        #expect(content.contains(##"filter: "drop-shadow(1px 2px 2px #000000)","##))
    }

    @Test("A line casts its outer shadow")
    func lineShadow() throws {
        let content = try card(##"{"type": "line", "id": "L1", "name": "Rule", "width": 120, "height": 0, "stroke": "#008888", "strokeWidth": 6, "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 1, "y": 2}, "blur": 4}}"##)
        #expect(content.contains(##"filter: "drop-shadow(1px 2px 2px #000000)","##))
    }

    @Test("An arc casts its outer shadow")
    func arcShadow() throws {
        let content = try card(##"{"type": "ellipse", "id": "E1", "name": "Arc", "width": 60, "height": 60, "sweepAngle": 90, "fill": "#335577", "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 1, "y": 2}, "blur": 4}}"##)
        #expect(content.contains(##"filter: "drop-shadow(1px 2px 2px #000000)","##))
    }

    @Test("A group casts its outer shadows over its content through a drop-shadow filter")
    func groupShadow() throws {
        let content = try card(##"""
        {"type": "group", "id": "G1", "name": "Pair", "effect": \##(Self.twoShadows),
         "children": [{"type": "rectangle", "id": "R1", "name": "Chip", "x": 0, "y": 0, "width": 70, "height": 70, "fill": "#FF8800"}]}
        """##)
        #expect(content.contains(##"filter: "drop-shadow(2px 2px 1.5px #FF0000) drop-shadow(0px 4px 4px #00000080)","##))
    }

    @Test("A group's layer blur blurs its content")
    func groupBlur() throws {
        let content = try card(##"""
        {"type": "group", "id": "G1", "name": "Pair", "effect": {"type": "blur", "radius": 6},
         "children": [{"type": "rectangle", "id": "R1", "name": "Chip", "x": 0, "y": 0, "width": 70, "height": 70, "fill": "#FF8800"}]}
        """##)
        #expect(content.contains(##"filter: "blur(3px)","##))
    }

    // MARK: - Order, blend modes, radii (criterion b)

    @Test("A box's shadows stack in Pen's order: CSS paints the first box-shadow on top, so the last comes first")
    func boxShadowOrder() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF", "effect": \##(Self.twoShadows)}"##)
        #expect(content.contains(##"boxShadow: "2px 2px 3px #FF0000, 0px 4px 8px #00000080","##))
    }

    @Test("The stroke is drawn over the inner shadow, as Pen draws it")
    func strokeOverInnerShadow() throws {
        let content = try card(##"""
        {"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF",
         "stroke": "#0000FF", "strokeWidth": 12, "strokeAlignment": "inner",
         "effect": {"type": "shadow", "shadowType": "inner", "color": "#000000FF", "offset": {"x": 8, "y": 8}, "blur": 16}}
        """##)
        #expect(content.contains(##"boxShadow: "inset 0 0 0 12px #0000FF, inset 8px 8px 16px #000000FF","##))
    }

    @Test("A layer blur keeps the fraction of half its radius")
    func blurKeepsFraction() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF", "effect": {"type": "blur", "radius": 5}}"##)
        #expect(content.contains(##"filter: "blur(2.5px)","##))
    }

    @Test("A shadow's fractional offset and blur are kept")
    func shadowKeepsFractions() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF", "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 0.5, "y": 1.5}, "blur": 2.5}}"##)
        #expect(content.contains(##"boxShadow: "0.5px 1.5px 2.5px #000000","##))
    }

    @Test("Several blurs write one filter, the first enabled blur as the renderer draws it")
    func blursShareOneFilter() throws {
        let content = try card(##"""
        {"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF",
         "effect": [{"type": "blur", "radius": 4, "enabled": false}, {"type": "blur", "radius": 6}, {"type": "blur", "radius": 10}]}
        """##)
        #expect(content.components(separatedBy: "filter:").count == 2)
        #expect(content.contains(##"filter: "blur(3px)","##))
    }

    @Test("A drop-shadow and a blur share one filter, the blur after the shadows")
    func shadowAndBlurShareOneFilter() throws {
        let content = try card(##"""
        {"type": "path", "id": "P1", "name": "Wedge", "width": 60, "height": 60, "geometry": "M0 60 L30 0 L60 60 Z", "fill": "#AA00AA",
         "effect": [{"type": "blur", "radius": 4}, {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 1, "y": 2}, "blur": 4}]}
        """##)
        #expect(content.contains(##"filter: "drop-shadow(1px 2px 2px #000000) blur(2px)","##))
    }

    @Test("A disabled shadow draws nothing")
    func disabledShadow() throws {
        let content = try card(##"{"type": "text", "id": "T1", "name": "Label", "content": "Hi", "effect": {"type": "shadow", "shadowType": "outer", "enabled": false, "blur": 4}}"##)
        #expect(!content.contains("textShadow"))
        #expect(!content.contains("filter"))
    }

    @Test("A shadow with no color is Pen's default, black at half alpha")
    func defaultShadowColor() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF", "effect": {"type": "shadow", "shadowType": "outer", "blur": 4}}"##)
        #expect(content.contains(##"boxShadow: "0px 0px 4px #00000080","##))
    }

    @Test("A blended outer shadow on a box is its own layer, blended, and keeps its place in the stack")
    func blendedBoxShadowIsALayer() throws {
        let content = try card(##"""
        {"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF", "cornerRadius": 8,
         "effect": [{"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 0, "y": 4}, "blur": 8},
                    {"type": "shadow", "shadowType": "outer", "color": "#FF0000", "offset": {"x": 2, "y": 2}, "blur": 3, "blendMode": "multiply"}]}
        """##)
        let black = try #require(content.range(of: ##"boxShadow: "0px 4px 8px #000000","##))
        let red = try #require(content.range(of: ##"boxShadow: "2px 2px 3px #FF0000","##))
        #expect(black.lowerBound < red.lowerBound, "the first shadow's layer comes first, so it paints below")
        #expect(content.contains(##"mixBlendMode: "multiply","##))
        #expect(content.contains(##"position: "relative","##))
        #expect(content.components(separatedBy: "aria-hidden").count == 3)
    }

    @Test("A blended shadow the page cannot layer is drawn unblended, with a warning")
    func blendedGlyphShadowWarns() throws {
        let diagnostics = PenDiagnosticCollector()
        let content = try card(
            ##"{"type": "text", "id": "T1", "name": "Label", "content": "Hi", "effect": {"type": "shadow", "shadowType": "outer", "color": "#FF0000", "blur": 3, "blendMode": "multiply"}}"##,
            diagnostics: diagnostics
        )
        #expect(content.contains(##"textShadow: "0px 0px 3px #FF0000","##))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "T1" && $0.message.contains("blend") })
    }

    // MARK: - Background blur (criterion c)

    @Test("A node with no visible fill writes no backdrop-filter")
    func noFillNoBackdrop() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "effect": {"type": "background_blur", "radius": 20}}"##)
        #expect(!content.contains("backdropFilter"))
    }

    @Test("A fully transparent fill writes no backdrop-filter")
    func transparentFillNoBackdrop() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF00", "effect": {"type": "background_blur", "radius": 20}}"##)
        #expect(!content.contains("backdropFilter"))
    }

    @Test("A visible fill keeps its backdrop-filter, at half the radius")
    func visibleFillBackdrop() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "name": "Box", "width": 80, "height": 80, "fill": "#FFFFFF01", "effect": {"type": "background_blur", "radius": 5}}"##)
        #expect(content.contains(##"backdropFilter: "blur(2.5px)","##))
        #expect(content.contains(##"WebkitBackdropFilter: "blur(2.5px)","##))
    }
}
