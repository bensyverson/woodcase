//
//  ReactEmitterGradientGeometryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter states a gradient's center, size and rotation in CSS, so a turned,
/// moved or sized gradient on a box that is not square draws where Pen draws it: a linear
/// gradient on a tile whose diagonal carries Pen's slant, an angular gradient turned (and,
/// on a stretched box, bent) to Pen's bearings, and a turned ellipse as an SVG paint server.
struct ReactEmitterGradientGeometryTests {
    // MARK: - Helpers

    /// The emitted `Card` component: a frame holding one child node, given as JSON.
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

    /// A `width` × `height` rectangle filled with a gradient whose own keys are `gradient`.
    private func rectangle(_ gradient: String, width: Int = 240, height: Int = 72, extra: String = "") throws -> String {
        try card(child: """
        {"type": "rectangle", "id": "Rect1", "name": "Box", "width": \(width), "height": \(height),
         "fill": {"type": "gradient", \(gradient)}\(extra)}
        """)
    }

    private static let ramp = ##""colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]"##

    // MARK: - Linear

    @Test("A 45° linear gradient runs along the box's diagonal, over Pen's unit length rather than corner to corner")
    func diagonalLinear() throws {
        let content = try rectangle(##""gradientType": "linear", "rotation": 45, "## + Self.ramp)
        #expect(content.contains(##"background: "linear-gradient(to top left, #FF0000 14.645%, #0000FF 85.355%)","##), "\(content)")
    }

    @Test("A sized linear gradient takes a tile whose diagonal carries its slant")
    func sizedLinear() throws {
        let content = try rectangle(
            ##""gradientType": "linear", "rotation": 30, "size": {"width": 0.5, "height": 0.6}, "## + Self.ramp,
            width: 72, height: 180
        )
        #expect(content.contains(
            ##"background: "linear-gradient(to top left, #FF0000 32.679%, #0000FF 67.321%) center / 173.205% 100% no-repeat","##
        ), "\(content)")
    }

    @Test("A moved upright gradient keeps its angle and moves its stops")
    func movedUprightLinear() throws {
        let content = try rectangle(##""gradientType": "linear", "center": {"x": 0.5, "y": 0.3}, "## + Self.ramp)
        #expect(content.contains(##"background: "linear-gradient(0deg, #FF0000 20%, #0000FF 120%)","##), "\(content)")
    }

    @Test("An off-axis gradient on a stroke overlay grows its tile past the stroke's reach")
    func overlayLinear() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Rect1", "name": "Box", "width": 200, "height": 120, "strokeWidth": 8,
         "stroke": {"type": "gradient", "gradientType": "linear", "rotation": 45, \(Self.ramp)}}
        """)
        #expect(content.contains(##"backgroundImage: "linear-gradient(to top left, #FF0000 16.854%, #0000FF 83.146%)","##), "\(content)")
        #expect(content.contains(##"backgroundSize: "calc((100% - 8px) * 1.06667) calc((100% - 8px) * 1.06667)","##), "\(content)")
    }

    // MARK: - Angular

    private static let wheel = ##""colors": [{"color": "#FF0000", "position": 0}, {"color": "#00FF00", "position": 0.5}, {"color": "#FF0000", "position": 1}]"##

    @Test("A turned angular gradient on a square box starts where Pen's rotation puts it")
    func turnedAngular() throws {
        let content = try rectangle(##""gradientType": "angular", "rotation": 90, "## + Self.wheel, width: 120, height: 120)
        #expect(content.contains(##"background: "conic-gradient(from 270deg, #FF0000 0%, #00FF00 50%, #FF0000 100%)","##), "\(content)")
    }

    @Test("A moved angular gradient turns about its center")
    func movedAngular() throws {
        let content = try rectangle(
            ##""gradientType": "angular", "center": {"x": 0.3, "y": 0.4}, "## + Self.wheel,
            width: 120, height: 120
        )
        #expect(content.contains(##"conic-gradient(from 0deg at 30% 40%, #FF0000 0%"##), "\(content)")
    }

    @Test("An angular gradient on a stretched box bends its stops to the box's bearings")
    func stretchedAngular() throws {
        let content = try rectangle(##""gradientType": "angular", "rotation": 45, "## + Self.wheel, width: 200, height: 100)
        let conic = try #require(content.firstMatch(of: /conic-gradient\(from ([0-9.]+)deg, ([^"]*)\)"/))
        #expect(conic.output.1 == "296.565")
        let stops = conic.output.2.split(separator: ", ")
        #expect(stops.count > 16, "\(stops.count) stops")
        #expect(stops.first == "#FF0000 0deg")
        #expect(stops.last == "#FF0000 360deg")
        // Pen's half turn lands on the opposite ray, which the stretch keeps opposite.
        #expect(stops.contains("#00FF00 180deg"), "\(stops)")
    }

    @Test("An angular gradient on a box with one side sized at layout time counts the box as square")
    func halfKnownBoxAngular() throws {
        let content = try card(child: """
        {"type": "text", "id": "Text1", "name": "Label", "width": 280, "textGrowth": "fixed-width", "content": "WWW",
         "fill": {"type": "gradient", "gradientType": "angular", "rotation": 90, \(Self.wheel)}}
        """)
        #expect(content.contains(##"backgroundImage: "conic-gradient(from 270deg, #FF0000 0%, #00FF00 50%, #FF0000 100%)","##), "\(content)")
    }

    // MARK: - Radial

    @Test("A quarter-turned sized radial gradient swaps its radii")
    func quarterTurnedRadial() throws {
        let content = try rectangle(
            ##""gradientType": "radial", "rotation": 90, "size": {"width": 0.5, "height": 1}, "## + Self.ramp
        )
        #expect(content.contains(##"radial-gradient(50% 25% at 50% 50%, #FF0000 0%, #0000FF 100%)"##), "\(content)")
    }

    @Test("A turned elliptical radial gradient is an SVG paint server stretched over the box")
    func turnedRadial() throws {
        let content = try rectangle(
            ##""gradientType": "radial", "rotation": 45, "size": {"width": 0.5, "height": 1}, "## + Self.ramp
        )
        let encoded = try #require(content.firstMatch(
            of: /background: "url\('data:image\/svg\+xml;base64,([A-Za-z0-9+\/=]+)'\) center \/ 100% 100% no-repeat"/
        ))
        let svg = try #require(Data(base64Encoded: String(encoded.output.1)).flatMap { String(data: $0, encoding: .utf8) })
        #expect(svg.contains(##"preserveAspectRatio="none""##), "\(svg)")
        #expect(svg.contains(##"gradientTransform="matrix(0.35355 -0.35355 0.70711 0.70711 0.5 0.5)""##), "\(svg)")
        #expect(svg.contains(##"<stop offset="1" stop-color="#0000FF"/>"##), "\(svg)")
    }
}
