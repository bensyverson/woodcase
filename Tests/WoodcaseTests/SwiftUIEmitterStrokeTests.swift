//
//  SwiftUIEmitterStrokeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a node's stroke becomes in emitted SwiftUI, over small synthetic documents:
/// alignment, width, caps and joins, per-side widths, every paint a stroke can carry, and
/// where the stroke sits in Pen's paint order. ``SwiftUIRenderTests`` measures the same
/// decisions against Pen's exports of `render-per-side-strokes`, `render-stroke-fills` and
/// `render-shadows`.
struct SwiftUIEmitterStrokeTests {
    // MARK: - Uniform strokes

    @Test("A centered stroke of one color is SwiftUI's own stroke, in an overlay")
    func centeredStroke() throws {
        let code = try body(child: rect(##""stroke": "#FF0000", "strokeWidth": 2, "strokeAlignment": "center""##))
        #expect(code.contains(".overlay {\n"))
        #expect(code.contains("Rectangle()\n.stroke(Color(hex: 0xFF0000), lineWidth: 2)"))
    }

    @Test("A stroke with no width or alignment is Pen's default: 1 point, centered")
    func defaultStroke() throws {
        let code = try body(child: rect(##""stroke": "#FF0000""##))
        #expect(code.contains(".stroke(Color(hex: 0xFF0000), lineWidth: 1)"))
    }

    @Test("An inner stroke on a plain or generously rounded rectangle is strokeBorder")
    func innerStrokeBorder() throws {
        let plain = try body(child: rect(##""stroke": "#FF0000", "strokeWidth": 12, "strokeAlignment": "inner""##))
        #expect(plain.contains("Rectangle()\n.strokeBorder(Color(hex: 0xFF0000), lineWidth: 12)"))
        let rounded = try body(child: rect(##""cornerRadius": 6, "stroke": "#FF0000", "strokeWidth": 12, "strokeAlignment": "inner""##))
        #expect(rounded.contains(".strokeBorder(Color(hex: 0xFF0000), lineWidth: 12)"))
    }

    @Test("An inner stroke on a tightly rounded rectangle, or on an ellipse, is the stroke's own region")
    func innerStrokeRegion() throws {
        let tight = try body(child: rect(##""cornerRadius": 4, "stroke": "#FF0000", "strokeWidth": 12, "strokeAlignment": "inner""##))
        #expect(tight.contains(
            "RoundedRectangle(cornerRadius: 4, style: .circular).penStroke(.inside, lineWidth: 12)\n.fill(Color(hex: 0xFF0000))"
        ))
        let ellipse = try body(child: ##"{"type": "ellipse", "id": "e", "width": 30, "height": 20, "stroke": "#00FF00", "strokeWidth": 4, "strokeAlignment": "inner"}"##)
        #expect(ellipse.contains("Ellipse().penStroke(.inside, lineWidth: 4)\n.fill(Color(hex: 0x00FF00))"))
    }

    @Test("An outer stroke is the region outside the shape")
    func outerStroke() throws {
        let code = try body(child: rect(##""cornerRadius": 24, "stroke": "#FF0000", "strokeWidth": 16, "strokeAlignment": "outer""##))
        #expect(code.contains("RoundedRectangle(cornerRadius: 24, style: .circular).penStroke(.outside, lineWidth: 16)"))
    }

    @Test("Caps and joins other than butt and miter are a StrokeStyle")
    func capsAndJoins() throws {
        let keys = ##""stroke": "#FF0000", "strokeWidth": 2, "strokeLinecap": "round", "strokeLinejoin": "bevel""##
        let code = try body(child: rect(keys))
        #expect(code.contains(".stroke(Color(hex: 0xFF0000), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .bevel))"))
        let outer = try body(child: rect(##""stroke": "#FF0000", "strokeWidth": 2, "strokeLinejoin": "round", "strokeAlignment": "outer""##))
        #expect(outer.contains(".penStroke(.outside, style: StrokeStyle(lineWidth: 2, lineJoin: .round))"))
    }

    @Test("A zero width, a disabled paint or a stroke with no paint draws nothing")
    func noStroke() throws {
        let drawn = try body(child: rect(##""stroke": "#FF0000", "strokeWidth": 1"##))
        #expect(drawn.contains(".overlay"))
        let zero = try body(child: rect(##""stroke": "#FF0000", "strokeWidth": 0"##))
        #expect(!zero.contains(".overlay"))
        let disabled = try body(child: rect(##""stroke": {"type": "color", "color": "#FF0000", "enabled": false}, "strokeWidth": 2"##))
        #expect(!disabled.contains(".overlay"))
        let unpainted = try body(child: rect(##""strokeWidth": 2"##))
        #expect(!unpainted.contains(".overlay"))
    }

    /// A width variable is read through `PenTheme` now (SwiftUIEmitterThemeReadTests); only one
    /// the document does not define is left out, and it is named.
    @Test("A width that names a variable the document lacks is reported, not drawn")
    func widthVariable() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(child: rect(##""stroke": "#FF0000", "strokeWidth": "$w""##), diagnostics: diagnostics)
        #expect(!code.contains(".overlay"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the number variable $w") })
    }

    @Test("A drawn stroke draws no warning")
    func noWarning() throws {
        let diagnostics = PenDiagnosticCollector()
        _ = try body(child: rect(##""stroke": "#FF0000", "strokeWidth": 2"##), diagnostics: diagnostics)
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "r" })
    }

    // MARK: - Paints

    @Test("A gradient stroke is stroked with the gradient, laid out over the node's box")
    func gradientStroke() throws {
        let gradient = ##"{"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}], "rotation": 270}"##
        let code = try body(child: rect(##""stroke": \##(gradient), "strokeWidth": 16"##))
        #expect(code.contains(".stroke(.linearGradient("))
        #expect(code.contains("lineWidth: 16)"))
    }

    @Test("A stack of stroke paints fills the stroke's region, each lower paint a background in it")
    func stackedStroke() throws {
        let stack = ##"["#FF0000", {"type": "color", "color": "#0000FF80"}]"##
        let code = try body(child: rect(##""stroke": \##(stack), "strokeWidth": 24"##))
        #expect(code.contains("Rectangle().penStroke(.center, lineWidth: 24)\n.fill(Color(hex: 0x0000FF, opacity: 0.502))"))
        #expect(code.contains(".background(Color(hex: 0xFF0000), in: Rectangle().penStroke(.center, lineWidth: 24))"))
    }

    @Test("An image stroke is the placed image, clipped to the stroke's region")
    func imageStroke() throws {
        let image = ##"{"type": "image", "url": "./images/uv.png", "mode": "stretch"}"##
        let code = try body(child: rect(##""stroke": \##(image), "strokeWidth": 16, "strokeAlignment": "outer""##))
        #expect(code.contains("ZStack {"))
        #expect(code.contains(".clipShape(Rectangle().penStroke(.outside, lineWidth: 16))"))
    }

    @Test("A gradient drawn as a view is given room past the box, which a stroke outside it covers")
    func gradientViewBleeds() throws {
        let angular = ##"{"type": "gradient", "gradientType": "angular", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}"##
        let code = try body(child: rect(##""stroke": \##(angular), "strokeWidth": 24"##))
        let bleed = try #require(code.range(of: ".penPaintBleed(120)"))
        let clip = try #require(code.range(of: ".clipShape(Rectangle().penStroke(.center, lineWidth: 24))"))
        #expect(bleed.lowerBound < clip.lowerBound)
        let inner = try body(child: rect(##""stroke": \##(angular), "strokeWidth": 24, "strokeAlignment": "inner""##))
        #expect(!inner.contains(".penPaintBleed"))
        let image = try body(child: rect(##""stroke": {"type": "image", "url": "./a.png"}, "strokeWidth": 24"##))
        #expect(!image.contains(".penPaintBleed"))
        #expect(try #require(SwiftUIEmitter.supportTemplates()["PenSupport+Paint.swift"]).contains("func penPaintBleed("))
    }

    @Test("A stroke's image is bundled with the package, like a fill's")
    func strokeImageBundled() throws {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "stroke": {"type": "image", "url": "./images/uv.png"}, "children": []}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let node = try #require(document.children.first)
        #expect(SwiftUIEmitter.imageAssetURLs(in: node) == ["./images/uv.png"])
    }

    // MARK: - A box that is a point

    @Test("A uniform stroke on a 0×0 layout-none frame is laid out from the box, as a per-side one is")
    func zeroAreaFrameStroke() throws {
        // Pen paints an 8 pt outer stroke on a sizeless absolute frame as a 16×16 square
        // about its point (`render-sizeless-frames.pen`, board `paint`); SwiftUI, like Core
        // Graphics, strokes nothing along a path of no length.
        let inner = rect(##""fill": "#FF00FF""##)
        let frame = ##"{"type": "frame", "id": "f", "layout": "none", "stroke": "#00FF00", "strokeWidth": 8, "strokeAlignment": "outer", "children": [\##(inner)]}"##
        let code = try body(child: frame)
        #expect(code.contains("PenSideStroke(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), alignment: .outside)"))
        // SwiftUI draws nothing under a point, so the stroke is drawn in a box grown by its
        // reach and inset back, as a flat shape's is.
        #expect(code.contains(".penOutset(dx: 8, dy: 8)"))
        #expect(code.contains(".padding(-8)"))
    }

    // MARK: - Per-side strokes

    @Test("A per-side stroke is PenSideStroke, its widths as EdgeInsets")
    func perSide() throws {
        let keys = ##""stroke": "#FFFFFF", "strokeWidth": {"top": 4, "right": 16, "bottom": 24, "left": 8}, "strokeAlignment": "inner""##
        let code = try body(child: rect(keys))
        #expect(code.contains(
            "PenSideStroke(EdgeInsets(top: 4, leading: 8, bottom: 24, trailing: 16), alignment: .inside)\n.fill(Color(hex: 0xFFFFFF))"
        ))
    }

    @Test("A per-side stroke defaults to centered, leaves missing sides at zero and carries the corners")
    func perSideCorners() throws {
        let keys = ##""cornerRadius": [24, 24, 0, 0], "stroke": "#FFFFFF", "strokeWidth": {"top": 4}"##
        let code = try body(child: rect(keys))
        #expect(code.contains(
            "PenSideStroke(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0), alignment: .center, cornerRadii: RectangleCornerRadii(topLeading: 24, topTrailing: 24))"
        ))
    }

    @Test("A per-side stroke on an ellipse is a stroke of its top width all round, as Pen draws it")
    func perSideEllipse() throws {
        let child = ##"{"type": "ellipse", "id": "e", "width": 30, "height": 20, "stroke": "#FFFFFF", "strokeWidth": {"top": 2, "left": 3}}"##
        let code = try body(child: child)
        #expect(code.contains("Ellipse()\n.stroke(Color(hex: 0xFFFFFF), lineWidth: 2)"), "\(code)")
        #expect(!code.contains("penSideBands"))
    }

    @Test("A per-side stroke on a polygon keeps its alignment at the top width")
    func perSidePolygonAligned() throws {
        let child = ##"{"type": "polygon", "id": "p", "width": 30, "height": 20, "polygonCount": 6, "stroke": "#FFFFFF", "##
            + ##""strokeWidth": {"top": 12, "right": 2, "bottom": 6}, "strokeAlignment": "inner"}"##
        let code = try body(child: child)
        #expect(code.contains(".penStroke(.inside, lineWidth: 12)"), "\(code)")
        #expect(!code.contains("penSideBands"))
    }

    @Test("A per-side stroke with no top on a path draws no stroke")
    func perSidePathWithoutTop() throws {
        let child = ##"{"type": "path", "id": "p", "width": 30, "height": 20, "geometry": "M0 0 L30 20", "fill": "#000000", "##
            + ##""stroke": "#FFFFFF", "strokeWidth": {"right": 10, "left": 6}}"##
        let code = try body(child: child)
        #expect(!code.contains(".stroke("), "\(code)")
        #expect(!code.contains("penStroke"), "\(code)")
        #expect(!code.contains("penSideBands"), "\(code)")
    }

    /// A per-side width variable is read through `PenTheme` now (SwiftUIEmitterThemeReadTests);
    /// only one the document does not define is left out, and it is named.
    @Test("A per-side width naming a variable the document lacks is reported, not drawn")
    func perSideVariableUndefined() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(
            child: rect(##""stroke": "#FF0000", "strokeWidth": {"top": "$missingEdge", "right": 2}"##), diagnostics: diagnostics
        )
        #expect(!code.contains("PenSideStroke"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("the number variable $missingEdge") })
    }

    @Test("A per-side stroke on a flat rectangle is the box's side stroke, outset to draw")
    func perSideFlatRectangle() throws {
        let child = ##"{"type": "rectangle", "id": "r", "width": 40, "height": 0, "stroke": "#FF0000", "strokeWidth": {"top": 4}}"##
        let code = try body(child: child)
        #expect(code.contains(
            "PenSideStroke(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0), alignment: .center).penOutset(dx: 0, dy: 4)"
        ), "\(code)")
        #expect(!code.contains("penSideBands"))
    }

    // MARK: - Paint order

    @Test("On a shape the stroke is drawn above its inner shadow")
    func strokeAboveInnerShadow() throws {
        let effect = ##"{"type": "shadow", "shadowType": "inner", "color": "#000000", "blur": 16}"##
        let code = try body(child: rect(##""fill": "#FFFFFF", "stroke": "#0000FF", "strokeWidth": 12, "effect": \##(effect)"##))
        let shadow = try #require(code.range(of: ".penInnerShadow("))
        let stroke = try #require(code.range(of: ".strokeBorder(") ?? code.range(of: ".stroke("))
        #expect(shadow.lowerBound < stroke.lowerBound)
    }

    @Test("On a frame with children the stroke sits over the inner shadow, under the children, outside the clip")
    func frameStrokeOrder() throws {
        let effect = ##"{"type": "shadow", "shadowType": "inner", "color": "#000000", "blur": 24}"##
        let frame = ##"{"type": "frame", "id": "f", "width": 100, "height": 100, "clip": true, "fill": "#FFFFFF", "stroke": "#FF0000", "strokeWidth": 4, "strokeAlignment": "outer", "effect": \##(effect), "children": [\##(rect(""))]}"##
        let code = try body(child: frame)
        let clip = try #require(code.range(of: ".clipped()"))
        let stroke = try #require(code.range(of: "Rectangle().penStroke(.outside, lineWidth: 4)"))
        let shadow = try #require(code.range(of: "PenInnerShadow(Rectangle()"))
        let fill = try #require(code.range(of: ".background(Color(hex: 0xFFFFFF))"))
        #expect(clip.lowerBound < stroke.lowerBound)
        #expect(stroke.lowerBound < shadow.lowerBound)
        #expect(shadow.lowerBound < fill.lowerBound)
    }

    @Test("An empty frame's stroke is an overlay, like a rectangle's")
    func emptyFrameStroke() throws {
        let code = try body(child: ##"{"type": "frame", "id": "f", "width": 40, "height": 40, "stroke": "#FF0000", "strokeWidth": 2}"##)
        #expect(code.contains(".overlay {"))
        #expect(code.contains(".stroke(Color(hex: 0xFF0000), lineWidth: 2)"))
    }

    // MARK: - Support

    @Test("The support files carry the stroke shapes")
    func supportFiles() throws {
        let support = try SwiftUIEmitter.supportTemplates()
        let stroke = try #require(support["PenSupport+Stroke.swift"])
        #expect(stroke.contains("struct PenStrokeRegion"))
        #expect(stroke.contains("enum PenStrokeAlignment"))
        #expect(stroke.contains("struct PenSideStroke"))
        #expect(!stroke.contains("PenSideBands"))
    }

    // MARK: - Helpers

    private func rect(_ keys: String) -> String {
        let separator = keys.isEmpty ? "" : ", "
        return ##"{"type": "rectangle", "id": "r", "width": 40, "height": 30\##(separator)\##(keys)}"##
    }

    private func body(child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        let content = try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
        // Indentation depends on nesting; the tests pin what is written, not where.
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop { $0 == " " } }
            .joined(separator: "\n")
    }
}
