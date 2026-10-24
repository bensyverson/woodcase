//
//  PenStrokeMissingWidthTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A stroke paint with no `strokeWidth` draws no stroke, on every kind of node, in every
/// target — as Pen draws it.
///
/// `render-stroke-no-width.pen` holds a rectangle, an ellipse, a frame, a polygon, a path
/// and a line, each stroked `#FF0000` with no width, beside controls that still draw: a
/// uniform width of 4, per-side objects with sides left out (a left-out side is no stroke
/// there; an ellipse with no `top` draws none), and widths bound to a variable, uniform and
/// per side (`scripts/pen-oracle … --scale 2`, pen CLI 0.3.13, 2026-10-23; leaf oMI28U).
struct PenStrokeMissingWidthTests {
    private static let fixture = "render-stroke-no-width"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard of the fixture, in document order.
    private static let artboards = [
        "rect-none", "ellip-none", "frame-none", "polyg-none", "pathx-none",
        "line-none", "rect-w4", "ellip-w4", "line-w4", "frame-topleft",
        "rect-bottom", "rect-nosides", "ellip-right", "rect-var", "rect-varsides",
    ]

    /// The criterion: within MAE 0.5 of Pen's export.
    private static let limit = 0.5

    /// Each kind of node that takes a stroke, 60 × 60 (a line 60 long), stroked red with no width.
    static let unwidened = [
        ##"{"type": "rectangle", "id": "Shp01", "name": "Shape", "width": 60, "height": 60, "stroke": "#FF0000"}"##,
        ##"{"type": "ellipse", "id": "Shp01", "name": "Shape", "width": 60, "height": 60, "stroke": "#FF0000"}"##,
        ##"{"type": "frame", "id": "Shp01", "name": "Shape", "layout": "none", "width": 60, "height": 60, "stroke": "#FF0000"}"##,
        ##"{"type": "polygon", "id": "Shp01", "name": "Shape", "width": 60, "height": 60, "stroke": "#FF0000"}"##,
        ##"{"type": "path", "id": "Shp01", "name": "Shape", "width": 60, "height": 60, "geometry": "M0 0 L60 0 L60 60 Z", "stroke": "#FF0000"}"##,
        ##"{"type": "line", "id": "Shp01", "name": "Shape", "width": 60, "height": 0, "stroke": "#FF0000"}"##,
        ##"{"type": "rectangle", "id": "Shp01", "name": "Shape", "width": 60, "height": 60, "stroke": \##(gradient)}"##,
        ##"{"type": "frame", "id": "Shp01", "name": "Shape", "layout": "none", "width": 60, "height": 60, "stroke": \##(gradient)}"##,
    ]

    /// A painted stroke, which React and SwiftUI draw apart from a plain color.
    private static let gradient = ##"{"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#FF0000", "position": 1}]}"##

    // MARK: - Against Pen

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each board draws within MAE 0.5 of Pen's export", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: 2
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        #expect(mae < Self.limit, "\(artboard): MAE \(mae)")
    }

    // MARK: - The model

    @Test("An absent width is a uniform width of zero")
    func absentUniformWidthIsZero() {
        #expect(PenNode.RectangleData(stroke: .single(.shorthand("#FF0000"))).uniformStrokeWidth == 0)
        #expect(PenNode.RectangleData(strokeWidth: .uniform(.literal(3))).uniformStrokeWidth == 3)
    }

    @Test("A stroke with no width is drawn with no paint, on every kind", arguments: unwidened)
    func drawnHasNoPaint(child: String) throws {
        let node = try Self.node(child)
        let stroke = try #require(PenLayoutEngine.strokable(node))
        #expect(stroke.stroke != nil)
        #expect(stroke.drawn(on: node).stroke == nil)
    }

    @Test("A stroke with no width adds no ink to the node's own", arguments: unwidened.filter { !$0.contains("line") && !$0.contains("gradient") })
    func ownInkIsUnchanged(child: String) throws {
        let box = PenRect(x: 0, y: 0, width: 60, height: 60)
        let unstroked = try Self.node(child.replacingOccurrences(of: ##", "stroke": "#FF0000""##, with: ""))
        let unpainted = try #require(PenLayoutEngine.ownInk(of: unstroked, box: box))
        #expect(try PenLayoutEngine.ownInk(of: Self.node(child), box: box) == unpainted)
    }

    @Test("A connection with no width draws nothing; one with a width draws")
    func connectionDrawsNothing() throws {
        #expect(try Self.connectionRedPixels(width: "") == 0)
        #expect(try Self.connectionRedPixels(width: #", "strokeWidth": 2"#) > 0)
    }

    // MARK: - Code generation

    @Test("React emits no stroke for a stroke with no width", arguments: unwidened)
    func reactEmitsNoStroke(child: String) throws {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "none",
           "width": 100, "height": 100, "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        #expect(!content.contains("FF0000"), "\(content)")
    }

    @Test("React's box stroke declarations are empty for a stroke with no width")
    func reactBoxStrokeIsEmpty() {
        #expect(ReactEmitter.emitStroke(PenNode.RectangleData(stroke: .single(.shorthand("#FF0000")))).isEmpty)
    }

    @Test("SwiftUI emits no stroke for a stroke with no width", arguments: unwidened)
    func swiftUIEmitsNoStroke(child: String) throws {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "layout": "none", "width": 100, "height": 100, "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: nil
        )
        let content = try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
        #expect(!content.contains("0xFF0000"), "\(content)")
    }

    #if os(macOS)
        @Test("SVG export writes no stroke for a stroke with no width", arguments: unwidened)
        func svgWritesNoStroke(child: String) throws {
            let fixture = try SVGExportFixture("[\(child)]")
            let xml = try #require(try fixture.svg(["Shp01"]))
            let stroked = try ["path", "line", "rect", "ellipse", "polygon"]
                .flatMap { try SVGExportFixture.elements($0, in: xml) }
                .filter { SVGExportFixture.attribute("stroke", of: $0).map { $0 != "none" } ?? false }
            #expect(stroked.isEmpty, "\(xml.xmlString)")
        }
    #endif

    // MARK: - Helpers

    /// The node `child` parses to.
    private static func node(_ child: String) throws -> PenNode {
        let document = try PenParser.parse(Data(##"{"version": "2.19", "children": [\##(child)]}"##.utf8))
        return try #require(document.children.first)
    }

    /// How many red pixels a connection between two blue boxes draws, its stroke keys closed
    /// with `width`.
    private static func connectionRedPixels(width: String) throws -> Int {
        let json = ##"""
        {"version": "2.19", "children": [
          {"type": "rectangle", "id": "a", "x": 10, "y": 10, "width": 20, "height": 20, "fill": "#0000FF"},
          {"type": "rectangle", "id": "b", "x": 70, "y": 10, "width": 20, "height": 20, "fill": "#0000FF"},
          {"type": "connection", "id": "c", "source": {"path": "a", "anchor": "right"},
           "target": {"path": "b", "anchor": "left"}, "stroke": "#FF0000"\##(width)}]}
        """##
        let document = try PenParser.parse(Data(json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 100, height: 40), scale: 4))
        return redPixels(in: image)
    }

    /// How many of `image`'s pixels are mostly red, on a transparent canvas: premultiplied, so a
    /// pixel the stroke half covers counts only when red is bright.
    private static func redPixels(in image: CGImage) -> Int {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: pixels.count, by: 4).count { pixels[$0] > 150 && pixels[$0] - pixels[$0 + 1] > 60 }
    }
}
