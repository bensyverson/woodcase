//
//  ReactEmitterSVGFillTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The `fill` attribute React writes on a shape it draws as SVG — a polygon, a path, an
/// arc or a donut.
///
/// Pen paints only enabled fills, the last over the others, so the one colour an SVG
/// `fill` can carry is the topmost enabled solid, and a shape with none is `fill="none"` —
/// the rule a text's and an icon's colour follow (`ReactEmitterUnfilledPaintTests`). Any
/// other fill — a gradient, an image, a mesh, a stack — is one filled copy of the shape per
/// layer, painted by a paint server laid out over the node's box, as Pen lays a fill out.
struct ReactEmitterSVGFillTests {
    /// A shape of each kind React writes as SVG, as a JSON object missing only its fill.
    static let shapes: [String] = [
        ##"{"type": "polygon", "id": "Shp01", "name": "Shape", "width": 40, "height": 40, "polygonCount": 6"##,
        ##"{"type": "path", "id": "Shp01", "name": "Shape", "width": 40, "height": 40, "geometry": "M0 0 L40 0 L40 40 Z""##,
        ##"{"type": "ellipse", "id": "Shp01", "name": "Shape", "width": 40, "height": 40, "sweepAngle": 270"##,
        ##"{"type": "ellipse", "id": "Shp01", "name": "Shape", "width": 40, "height": 40, "innerRadius": 0.5"##,
    ]

    /// The emitted `Card` component holding `shape` with `fill`.
    private func card(shape: String, fill: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(shape), "fill": \(fill)}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    @Test("A disabled colour under an enabled one is skipped", arguments: shapes)
    func skipsDisabled(shape: String) throws {
        let content = try card(shape: shape, fill: ##"[{"type": "color", "color": "#FF0000", "enabled": false}, "#0000FF"]"##)
        #expect(content.contains(##"fill="#0000FF""##), "\(content)")
        #expect(!content.contains("#FF0000"))
    }

    @Test("Only disabled fills is no fill", arguments: shapes)
    func onlyDisabledIsNone(shape: String) throws {
        let content = try card(shape: shape, fill: ##"[{"type": "color", "color": "#FF0000", "enabled": false}]"##)
        #expect(content.contains(##"fill="none""##), "\(content)")
        #expect(!content.contains("#FF0000"))
    }

    @Test("Of two enabled colours, the top one is the fill", arguments: shapes)
    func topColour(shape: String) throws {
        let content = try card(shape: shape, fill: ##"["#FF0000", "#0000FF"]"##)
        #expect(content.contains(##"fill="#0000FF""##), "\(content)")
    }

    // MARK: - Painted fills

    private static let gradient = ##"{"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}"##

    @Test("A gradient fill is a paint server laid out over the node's box", arguments: shapes)
    func gradientFill(shape: String) throws {
        let content = try card(shape: shape, fill: Self.gradient)
        #expect(content.contains(##"<linearGradient id="wc-paint-"##), "\(content)")
        #expect(content.contains(##"gradientUnits="userSpaceOnUse""##), "\(content)")
        #expect(content.contains(##"gradientTransform="matrix(40 0 "##), "\(content)")
        #expect(content.contains(##"fill="url(#wc-paint-"##), "\(content)")
    }

    @Test("An image fill is a pattern placing the image over the node's box", arguments: shapes)
    func imageFill(shape: String) throws {
        let content = try card(shape: shape, fill: ##"{"type": "image", "url": "https://example.com/a.png", "mode": "stretch"}"##)
        #expect(content.contains("<pattern id=\"wc-paint-"), "\(content)")
        #expect(content.contains(##"<image href="https://example.com/a.png""##), "\(content)")
        #expect(content.contains(##"fill="url(#wc-paint-"##), "\(content)")
    }

    @Test("A mesh fill is a pattern holding its raster", arguments: shapes)
    func meshFill(shape: String) throws {
        let mesh = ##"{"type": "mesh_gradient", "columns": 2, "rows": 2, "points": [[0, 0], [1, 0], [0, 1], [1, 1]], "##
            + ##""colors": ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF"]}"##
        let content = try card(shape: shape, fill: mesh)
        #expect(content.contains("<pattern id=\"wc-paint-"), "\(content)")
        #expect(content.contains(##"fill="url(#wc-paint-"##), "\(content)")
    }

    @Test("A colour under a gradient is two copies of the shape, the colour first", arguments: shapes)
    func stackedFills(shape: String) throws {
        let content = try card(shape: shape, fill: ##"["#00FF00", \##(Self.gradient)]"##)
        let colour = try #require(content.range(of: ##"fill="#00FF00""##), "\(content)")
        let gradient = try #require(content.range(of: ##"fill="url(#wc-paint-"##), "\(content)")
        #expect(colour.lowerBound < gradient.lowerBound)
    }

    @Test("A painted fill under a solid stroke keeps the stroke, over the fill and unfilled", arguments: shapes)
    func paintedFillUnderStroke(shape: String) throws {
        let content = try card(shape: shape, fill: ##"\##(Self.gradient), "stroke": "#000000", "strokeWidth": 2"##)
        let fill = try #require(content.range(of: ##"fill="url(#wc-paint-"##), "\(content)")
        let stroke = try #require(content.range(of: ##"fill="none" stroke="#000000""##), "\(content)")
        #expect(fill.lowerBound < stroke.lowerBound)
    }

    @Test("A painted fill under a painted stroke is drawn once, beneath the stroke's copies", arguments: shapes)
    func paintedFillUnderPaintedStroke(shape: String) throws {
        let content = try card(shape: shape, fill: ##"\##(Self.gradient), "stroke": \##(Self.gradient), "strokeWidth": 2"##)
        let fill = try #require(content.range(of: ##"fill="url(#wc-paint-"##), "\(content)")
        let stroke = try #require(content.range(of: ##"fill="none" stroke="url(#wc-paint-"##), "\(content)")
        #expect(fill.lowerBound < stroke.lowerBound)
        #expect(content.components(separatedBy: ##"fill="url(#wc-paint-"##).count == 2, "\(content)")
    }
}
