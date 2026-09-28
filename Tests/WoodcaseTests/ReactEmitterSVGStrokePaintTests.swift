//
//  ReactEmitterSVGStrokePaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter paints a stroke that is more than one plain colour on a node it
/// draws as SVG (path, polygon, arc or donut ellipse, line): each paint is a paint server
/// in `userSpaceOnUse` laid out over the node's box, and an inner or outer alignment is a
/// doubled stroke clipped to the shape or masked by it — Pen's own export construction.
struct ReactEmitterSVGStrokePaintTests {
    // MARK: - Helpers

    private func card(child: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    /// A 200 × 100 zig-zag path with `stroke` at width 12 and anything in `extra`.
    private func path(stroke: String, extra: String = "") throws -> String {
        try card(child: """
        {"type": "path", "id": "Path1", "name": "Zig", "width": 200, "height": 100,
         "geometry": "M0 0 L50 100 L100 0 L150 100 L200 0",
         "stroke": \(stroke), "strokeWidth": 12\(extra)}
        """)
    }

    private static let ramp = ReactEmitterStrokePaintTests.ramp

    /// The one paint-server id the content references, e.g. `wc-paint-0123456789ab`.
    private func paintID(in content: String) throws -> String {
        try String(#require(content.firstMatch(of: /url\(#(wc-paint-[0-9a-f]{12})\)/)).output.1)
    }

    // MARK: - Tests

    /// Green on its first run: it pins today's output, which the change must keep.
    @Test("A lone solid stroke stays a stroke attribute")
    func solidStaysAttribute() throws {
        let content = try path(stroke: "\"#FF0000\"")
        #expect(content.contains(##"stroke="#FF0000" strokeWidth="12""##))
        #expect(!content.contains("<defs>"))
    }

    @Test("A linear gradient stroke is Pen's unit gradient mapped onto the node box")
    func linearPaintServer() throws {
        let content = try path(stroke: Self.ramp)
        let id = try paintID(in: content)
        #expect(content.contains("<defs>"))
        #expect(content.contains(
            ##"<linearGradient id="\##(id)" gradientUnits="userSpaceOnUse" x1="0" y1="0.5" x2="0" y2="-0.5" gradientTransform="matrix(0 100 -200 0 100 50)">"##
        ))
        #expect(content.contains(##"<stop offset="0" style={{ stopColor: "#FF0000" }} />"##))
        #expect(content.contains(##"<stop offset="1" style={{ stopColor: "#0000FF" }} />"##))
        #expect(content.contains(##"fill="none" stroke="url(#\##(id))" strokeWidth="12""##))
        #expect(content.contains(##"overflow="visible""##))
    }

    @Test("A turned, off-centre, resized gradient keeps Pen's geometry in the normalised box")
    func turnedGradientMatrix() throws {
        let stroke = """
        {"type": "gradient", "gradientType": "linear", "rotation": 45,
         "center": {"x": 0.3, "y": 0.4}, "size": {"width": 1, "height": 0.6},
         "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}
        """
        let content = try path(stroke: stroke)
        #expect(content.contains(##"gradientTransform="matrix(141.421 -70.711 84.853 42.426 60 40)""##))
    }

    @Test("A radial gradient stroke is an ellipse touching the node box's sides")
    func radialPaintServer() throws {
        let stroke = """
        {"type": "gradient", "gradientType": "radial",
         "colors": [{"color": "#FFFF00", "position": 0}, {"color": "#00FFFF", "position": 1}]}
        """
        let content = try path(stroke: stroke)
        let id = try paintID(in: content)
        #expect(content.contains(
            ##"<radialGradient id="\##(id)" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="0.5" gradientTransform="matrix(200 0 0 100 100 50)">"##
        ))
    }

    @Test("An inner stroke is doubled and clipped to the shape")
    func innerIsClipped() throws {
        let content = try path(stroke: Self.ramp, extra: ##", "strokeAlignment": "inner""##)
        let clip = try String(#require(content.firstMatch(of: /<clipPath id="(wc-clip-[0-9a-f]{12})">/)).output.1)
        #expect(content.contains(##"strokeWidth="24" clipPath="url(#\##(clip))""##))
    }

    @Test("An outer stroke is doubled and masked by the shape")
    func outerIsMasked() throws {
        let content = try path(stroke: Self.ramp, extra: ##", "strokeAlignment": "outer""##)
        let mask = try String(#require(content.firstMatch(of: /<mask id="(wc-mask-[0-9a-f]{12})"/)).output.1)
        #expect(content.contains(##"strokeWidth="24" mask="url(#\##(mask))""##))
        #expect(content.contains(##"fill="white""##))
        #expect(content.contains(##"fill="black""##))
    }

    @Test("An image stroke is a pattern that draws the image once, over the node box")
    func imagePattern() throws {
        let content = try path(stroke: ##"{"type": "image", "url": "./images/uv.png", "mode": "stretch"}"##)
        let id = try paintID(in: content)
        #expect(content.contains(
            ##"<pattern id="\##(id)" patternUnits="userSpaceOnUse" x="-25" y="-25" width="250" height="150">"##
        ))
        #expect(content.contains(
            ##"<image href="./images/uv.png" x="25" y="25" width="200" height="100" preserveAspectRatio="none" />"##
        ))
    }

    @Test("Stacked stroke paints draw one stroke per layer, bottom first")
    func stackedLayers() throws {
        let content = try path(stroke: "[\"#00FF00\", \(Self.ramp)]")
        let solid = try #require(content.range(of: ##"stroke="#00FF00""##))
        let gradient = try #require(content.range(of: ##"stroke="url(#wc-paint-"##))
        #expect(solid.lowerBound < gradient.lowerBound)
    }

    @Test("A blended stroke layer blends through mix-blend-mode")
    func blendedLayer() throws {
        let blended = Self.ramp.replacingOccurrences(of: "\"linear\",", with: "\"linear\", \"blendMode\": \"multiply\",")
        let content = try path(stroke: "[\"#00FF00\", \(blended)]")
        #expect(content.contains(##"style={{ mixBlendMode: "multiply" }}"##))
    }

    @Test("A polygon's gradient stroke uses the same paint server")
    func polygonPaintServer() throws {
        let content = try card(child: """
        {"type": "polygon", "id": "Poly1", "width": 200, "height": 100, "polygonCount": 3,
         "stroke": \(Self.ramp), "strokeWidth": 4}
        """)
        let id = try paintID(in: content)
        #expect(content.contains(##"<polygon points="##))
        #expect(content.contains(##"stroke="url(#\##(id))" strokeWidth="4""##))
    }

    @Test("A donut ellipse's gradient stroke uses the same paint server")
    func donutPaintServer() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Donut", "width": 100, "height": 100, "innerRadius": 0.5,
         "stroke": \(Self.ramp), "strokeWidth": 4}
        """)
        let id = try paintID(in: content)
        #expect(content.contains(##"stroke="url(#\##(id))" strokeWidth="4""##))
    }

    @Test("A line's gradient stroke uses the same paint server")
    func linePaintServer() throws {
        let content = try card(child: """
        {"type": "line", "id": "Line1", "width": 200, "height": 0, "stroke": \(Self.ramp), "strokeWidth": 4}
        """)
        let id = try paintID(in: content)
        #expect(content.contains(##"<line x1="0" y1="0" x2="200" y2="0" stroke="url(#\##(id))" strokeWidth="4" />"##))
    }

    @Test("The paint server's id is stable across emissions")
    func stableIDs() throws {
        #expect(try paintID(in: path(stroke: Self.ramp)) == paintID(in: path(stroke: Self.ramp)))
    }
}
