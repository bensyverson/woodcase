//
//  SwiftUIEmitterShapeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What paths, polygons, lines, arcs, donuts and icons become in emitted SwiftUI, over
/// small synthetic documents. ``SwiftUIRenderTests`` measures the same decisions against
/// Pen's exports of `render-arc-donut`, `render-strokes-and-paths`, `render-fill-domains`
/// and `render-text-fills`' icon board.
struct SwiftUIEmitterShapeTests {
    // MARK: - Paths

    @Test("A path is a Shape of its own, declared in the page, drawn at its size and fitted to its box")
    func pathShape() throws {
        let code = try page(child: path(##""geometry": "M0 0 L10 20 L20 0", "fill": "#FF0000""##))
        #expect(code.contains("private struct ZigZagShape: Shape {"))
        #expect(code.contains("func path(in rect: CGRect) -> Path {"))
        #expect(code.contains("var path = Path()\npath.move(to: CGPoint(x: 0, y: 0))\npath.addLine(to: CGPoint(x: 10, y: 20))\npath.addLine(to: CGPoint(x: 20, y: 0))"))
        #expect(code.contains("return path.penFitted(from: CGSize(width: 20, height: 20), to: rect)"))
        #expect(code.contains("ZigZagShape()\n.fill(Color(hex: 0xFF0000))\n.frame(width: 20, height: 20)"))
    }

    @Test("A path's geometry is mapped through its viewBox, and its curves are written as curves")
    func viewBoxAndCurves() throws {
        let keys = ##""width": 200, "height": 120, "viewBox": [0, 0, 100, 100], "geometry": "M25 25 L75 25 Q75 75 25 75 C0 75 0 25 25 25 Z", "fill": "#FF0000""##
        let code = try page(child: ##"{"type": "path", "id": "p", "name": "blob", \##(keys)}"##)
        #expect(code.contains("path.move(to: CGPoint(x: 50, y: 30))"))
        #expect(code.contains("path.addQuadCurve(to: CGPoint(x: 50, y: 90), control: CGPoint(x: 150, y: 90))"))
        #expect(code.contains("path.addCurve(to: CGPoint(x: 50, y: 30), control1: CGPoint(x: 0, y: 90), control2: CGPoint(x: 0, y: 30))"))
        #expect(code.contains("path.closeSubpath()"))
    }

    @Test("An even-odd path is filled, backed and clipped even-odd")
    func evenOdd() throws {
        let code = try page(child: path(##""geometry": "M0 0 L20 0 L20 20 L0 20 Z M5 5 L15 5 L15 15 L5 15 Z", "fillRule": "evenodd", "fill": ["#00FF00", "#FF000080"]"##))
        #expect(code.contains(".fill(Color(hex: 0xFF0000, opacity: 0.502), style: FillStyle(eoFill: true))"))
        #expect(code.contains(".background(Color(hex: 0x00FF00), in: ZigZagShape(), fillStyle: FillStyle(eoFill: true))"))
    }

    @Test("Shapes that share a name get distinct types; a name that is not an identifier is made one")
    func shapeNames() throws {
        let second = ##"{"type": "path", "id": "q", "name": "zig zag", "width": 20, "height": 20, "geometry": "M0 0 L20 20"}"##
        let third = ##"{"type": "path", "id": "r", "name": "3d star", "width": 20, "height": 20, "geometry": "M0 0 L20 20"}"##
        let code = try page(child: "\(path(##""geometry": "M0 0 L20 20""##)), \(second), \(third)")
        #expect(code.contains("private struct ZigZagShape: Shape {"))
        #expect(code.contains("private struct ZigZagShape2: Shape {"))
        #expect(code.contains("private struct Node3dStarShape: Shape {"))
    }

    @Test("A path is stroked through its shape and casts its shadow from it and its stroke band; it is no placeholder")
    func pathStrokeAndShadow() throws {
        let diagnostics = PenDiagnosticCollector()
        let keys = ##""geometry": "M0 0 L10 20 L20 0", "stroke": "#0000FF", "strokeWidth": 4, "strokeLinecap": "round", "effect": {"type": "shadow", "color": "#000000", "blur": 4}"##
        let code = try page(child: path(keys), diagnostics: diagnostics)
        #expect(code.contains("ZigZagShape()\n.stroke(Color(hex: 0x0000FF), style: StrokeStyle(lineWidth: 4, lineCap: .round))"))
        #expect(code.contains(
            ".penDropShadow(PenSilhouette(ZigZagShape(), stroke: ZigZagShape().penStroke(.center, style: StrokeStyle(lineWidth: 4, lineCap: .round))), color: Color(hex: 0x000000), radius: 2)"
        ))
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "p" })
    }

    // MARK: - Polygons, lines, arcs

    @Test("A polygon is its vertices from the top, clockwise")
    func polygon() throws {
        let code = try page(child: ##"{"type": "polygon", "id": "g", "name": "tri", "width": 200, "height": 120, "polygonCount": 3, "fill": "#FF0000"}"##)
        #expect(code.contains("private struct TriShape: Shape {"))
        #expect(code.contains("path.move(to: CGPoint(x: 100, y: 0))\npath.addLine(to: CGPoint(x: 186.60254, y: 90))"))
    }

    @Test("A rounded polygon's corners are tangent arcs")
    func roundedPolygon() throws {
        let code = try page(child: ##"{"type": "polygon", "id": "g", "name": "hex", "width": 100, "height": 100, "polygonCount": 6, "cornerRadius": 8, "fill": "#FF0000"}"##)
        #expect(code.contains("path.addArc(tangent1End: CGPoint("))
        #expect(code.contains("radius: 8)"))
    }

    @Test("A line runs from its box's top left to its bottom right, stroked")
    func line() throws {
        let code = try page(child: ##"{"type": "line", "id": "l", "name": "rule", "width": 150, "height": 30, "stroke": "#333333", "strokeWidth": 2}"##)
        #expect(code.contains("path.move(to: CGPoint(x: 0, y: 0))\npath.addLine(to: CGPoint(x: 150, y: 30))"))
        #expect(code.contains("return path.penFitted(from: CGSize(width: 150, height: 30), to: rect)"))
        #expect(code.contains("RuleShape()\n.stroke(Color(hex: 0x333333), lineWidth: 2)"))
    }

    @Test("A line of no height is stroked in a box its stroke's reach taller, which SwiftUI draws; its layout box stays flat")
    func flatLine() throws {
        let code = try page(child: ##"{"type": "line", "id": "l", "name": "rule", "width": 150, "height": 0, "stroke": "#333333", "strokeWidth": 2}"##)
        #expect(code.contains("return path.penFitted(from: CGSize(width: 150, height: 0), to: rect)"))
        #expect(code.contains("Color.clear\n.frame(width: 150, height: 0)\n.overlay {"))
        #expect(code.contains("RuleShape().penOutset(dx: 0, dy: 2)\n.stroke(Color(hex: 0x333333), lineWidth: 2)\n.padding(.vertical, -2)"))
    }

    @Test("A line of no width is stroked in a box its stroke's reach wider; a hairline reaches a whole point")
    func uprightHairline() throws {
        let code = try page(child: ##"{"type": "line", "id": "l", "name": "rule", "width": 0, "height": 80, "stroke": "#333333", "strokeWidth": 0.5}"##)
        #expect(code.contains("RuleShape().penOutset(dx: 1, dy: 0)\n.stroke(Color(hex: 0x333333), lineWidth: 0.5)\n.padding(.horizontal, -1)"))
    }

    @Test("A stroked rectangle under a point on both axes is outset on both")
    func pointRectangle() throws {
        let code = try page(child: ##"{"type": "rectangle", "id": "r", "width": 0.5, "height": 0.5, "stroke": "#333333", "strokeWidth": 4}"##)
        #expect(code.contains("Rectangle().penOutset(dx: 4, dy: 4)\n.stroke(Color(hex: 0x333333), lineWidth: 4)\n.padding(-4)"))
    }

    @Test("The support file defines penOutset, which draws a shape inset in the box it is offered")
    func supportDefinesOutset() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates["PenSupport+Shape.swift"])
        #expect(support.contains("func penOutset(dx: CGFloat, dy: CGFloat) -> PenOutsetShape<Self>"))
        #expect(support.contains("struct PenOutsetShape<S: Shape>: Shape"))
    }

    /// Core Text moves a variable font's `opsz` axis to the point size unless told not to;
    /// Pen draws a Material Symbols icon at the font's default optical size at every size.
    @Test("The support file draws an icon font with automatic optical sizing off")
    func supportPinsIconOpticalSize() throws {
        let fonts = try #require(SwiftUIEmitter.supportTemplates["PenSupport+Fonts.swift"])
        let body = try #require(fonts.firstRange(of: "static func font(file: String").map { fonts[$0.lowerBound...] })
        let function = try body[..<#require(body.firstRange(of: "\n    }\n")).lowerBound]
        #expect(function.contains("kCTFontOpticalSizeAttribute: \"none\""))
    }

    @Test("An arc is an elliptical arc through the unit circle, scaled to the ellipse")
    func arc() throws {
        let diagnostics = PenDiagnosticCollector()
        let child = ##"{"type": "ellipse", "id": "e", "name": "slice", "width": 200, "height": 120, "sweepAngle": 90, "fill": "#FFFFFF"}"##
        let code = try page(child: child, diagnostics: diagnostics)
        #expect(code.contains(
            "path.addArc(center: .zero, radius: 1, startAngle: .radians(0), endAngle: .radians(-1.570796), clockwise: true, transform: CGAffineTransform(translationX: 100, y: 60).scaledBy(x: 100, y: 60))"
        ))
        #expect(code.contains("SliceShape()\n.fill(Color(hex: 0xFFFFFF))"))
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "e" })
    }

    @Test("A full ring is two ellipses filled even-odd; a plain ellipse stays Ellipse()")
    func ring() throws {
        let ring = try page(child: ##"{"type": "ellipse", "id": "e", "name": "ring", "width": 200, "height": 120, "innerRadius": 0.5, "fill": "#FFFFFF"}"##)
        #expect(ring.contains("path.addEllipse(in: CGRect(x: 0, y: 0, width: 200, height: 120))\npath.addEllipse(in: CGRect(x: 50, y: 30, width: 100, height: 60))"))
        #expect(ring.contains(".fill(Color(hex: 0xFFFFFF), style: FillStyle(eoFill: true))"))
        let plain = try page(child: ##"{"type": "ellipse", "id": "e", "width": 20, "height": 20, "fill": "#FFFFFF"}"##)
        #expect(plain.contains("Ellipse()\n.fill(Color(hex: 0xFFFFFF))"))
        #expect(!plain.contains(": Shape {"))
    }

    // MARK: - Icons

    @Test("An icon is its glyph as a shape from the bundled font, painted with its fills")
    func icon() throws {
        let glyph = try #require(PenIconFontRegistry.shared.codepoint(family: "lucide", name: "star"))
        let hex = String(glyph, radix: 16, uppercase: true)
        let code = try page(child: ##"{"type": "icon", "id": "i", "width": 24, "height": 24, "library": "lucide", "icon": "star", "fill": "#FF0000"}"##)
        #expect(code.contains("PenIconShape(file: \"lucide.ttf\", glyph: 0x\(hex))\n.fill(Color(hex: 0xFF0000))\n.frame(width: 24, height: 24)"))
    }

    @Test("A Material Symbols icon carries its weight, Pen's default 200 when unset")
    func materialIconWeight() throws {
        let code = try page(child: ##"{"type": "icon", "id": "i", "width": 24, "height": 24, "library": "Material Symbols Outlined", "icon": "home", "fill": "#000000"}"##)
        #expect(code.contains("PenIconShape(file: \"MaterialSymbolsOutlined.ttf\", glyph: 0x"))
        #expect(code.contains(", weight: 200)\n"))
    }

    @Test("An unknown icon name draws the library's own question mark, as Pen does")
    func unknownIcon() throws {
        let glyph = try #require(PenIconFontRegistry.shared.placeholder(family: "lucide")?.codepoint)
        let code = try page(child: ##"{"type": "icon", "id": "i", "width": 24, "height": 24, "library": "lucide", "icon": "no-such-icon", "fill": "#000000"}"##)
        #expect(code.contains("glyph: 0x\(String(glyph, radix: 16, uppercase: true))"))
    }

    @Test("An icon from a library with no bundled font is a placeholder with a warning")
    func unknownLibrary() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try page(
            child: ##"{"type": "icon", "id": "i", "width": 24, "height": 24, "library": "nope", "icon": "star"}"##,
            diagnostics: diagnostics
        )
        #expect(code.contains("Color.clear"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "i" && $0.message.contains("the icon library \"nope\"") })
    }

    @Test("The icon libraries a page draws are reported, and bundle the package's resources")
    func iconLibrariesBundled() throws {
        let result = try emit(child: ##"{"type": "icon", "id": "i", "width": 24, "height": 24, "library": "lucide", "icon": "star"}"##)
        #expect(result.iconLibraries == ["lucide"])
        let manifest = try #require(result.files.first { $0.path == "Package.swift" })
        #expect(manifest.content.contains(".process(\"Resources\")"))
        #expect(SwiftUIEmitter.iconFontFiles(for: "lucide").map(\.lastPathComponent) == ["lucide.ttf"])
    }

    @Test("A path's image fill is bundled")
    func pathImageBundled() throws {
        let result = try emit(child: path(##""geometry": "M0 0 L20 20", "fill": {"type": "image", "url": "./images/a.png"}"##))
        #expect(result.imageAssetURLs == ["./images/a.png"])
    }

    @Test("The support files carry the fitted path and the icon shape")
    func supportFiles() throws {
        let shape = try #require(SwiftUIEmitter.supportTemplates["PenSupport+Shape.swift"])
        #expect(shape.contains("func penFitted(from size: CGSize, to rect: CGRect) -> Path"))
        #expect(shape.contains("struct PenIconShape: Shape"))
    }

    // MARK: - Helpers

    private func path(_ keys: String) -> String {
        ##"{"type": "path", "id": "p", "name": "zig zag", "width": 20, "height": 20, \##(keys)}"##
    }

    private func emit(child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> EmitResult {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        return SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
    }

    /// The page's source with every line's indentation dropped: the tests pin what is
    /// written, not where.
    private func page(child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let result = try emit(child: child, diagnostics: diagnostics)
        let content = try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop { $0 == " " } }
            .joined(separator: "\n")
    }
}
