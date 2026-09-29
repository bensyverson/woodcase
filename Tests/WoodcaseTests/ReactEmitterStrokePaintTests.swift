//
//  ReactEmitterStrokePaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter paints a stroke on a box (rectangle, frame, CSS ellipse) that is
/// more than one plain color: an absolutely positioned overlay the size of the stroke's
/// outer edge, whose transparent border puts its padding box on the node's box (Pen's
/// paint domain, `project/2026-09-26-text-and-stroke-fills.md` finding 2), whose padding
/// puts its content box on the stroke's inner edge, and whose mask cuts the content box
/// out — leaving the ring.
struct ReactEmitterStrokePaintTests {
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

    /// A 200 × 120 rectangle with `stroke`, `strokeWidth` and anything in `extra`.
    private func rectangle(stroke: String, width: String = "8", extra: String = "") throws -> String {
        try card(child: """
        {"type": "rectangle", "id": "Rect1", "name": "Box", "width": 200, "height": 120,
         "stroke": \(stroke), "strokeWidth": \(width)\(extra)}
        """)
    }

    static let ramp = """
    {"type": "gradient", "gradientType": "linear", "rotation": 270,
     "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}
    """

    private static let ringMask = [
        ##"WebkitMask: "linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)","##,
        ##"WebkitMaskComposite: "xor","##,
        ##"mask: "linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0)","##,
    ]

    // MARK: - The plain-color route

    @Test("A lone solid stroke stays box-shadows, with no overlay")
    func solidStaysBoxShadow() throws {
        let content = try rectangle(stroke: "\"#FF0000\"")
        // Centered: half inside the edge, half outside (ReactEmitterStrokePlacementTests).
        #expect(content.contains(##"boxShadow: "inset 0 0 0 4px #FF0000, 0 0 0 4px #FF0000","##))
        #expect(!content.contains("aria-hidden"))
    }

    @Test("A disabled solid stroke draws nothing")
    func disabledSolidDrawsNothing() throws {
        let content = try rectangle(stroke: ##"{"type": "color", "color": "#FF0000", "enabled": false}"##)
        #expect(!content.contains("boxShadow"))
        #expect(!content.contains("aria-hidden"))
    }

    // MARK: - The overlay

    @Test("A gradient inner stroke overlays the node box, padded in by the width")
    func innerGradientOverlay() throws {
        let content = try rectangle(stroke: Self.ramp, extra: ##", "strokeAlignment": "inner""##)
        #expect(content.contains(##"position: "relative","##))
        #expect(content.contains(##"aria-hidden="true""##))
        #expect(content.contains(##"position: "absolute","##))
        #expect(content.contains("inset: 0,"))
        #expect(content.contains(##"padding: "8px","##))
        #expect(!content.contains("borderWidth"))
        #expect(content.contains(##"backgroundImage: "linear-gradient(-270deg, #FF0000 0%, #0000FF 100%)","##))
        #expect(content.contains(##"backgroundOrigin: "border-box","##))
        #expect(content.contains(##"pointerEvents: "none","##))
        for declaration in Self.ringMask {
            #expect(content.contains(declaration), "missing \(declaration)")
        }
        #expect(!content.contains("boxShadow"))
    }

    @Test("A centered stroke straddles the edge and pads the gradient out to the node box")
    func centerGradientOverlay() throws {
        let content = try rectangle(stroke: Self.ramp)
        #expect(content.contains(##"inset: "-4px","##))
        #expect(content.contains(##"borderStyle: "solid","##))
        #expect(content.contains(##"borderColor: "transparent","##))
        #expect(content.contains(##"borderWidth: "4px","##))
        #expect(content.contains(##"padding: "4px","##))
        #expect(content.contains(
            ##"backgroundImage: "linear-gradient(-270deg, #FF0000 4px, #0000FF calc(100% - 4px))","##
        ))
    }

    @Test("An outer stroke sits wholly outside the node box")
    func outerGradientOverlay() throws {
        let content = try rectangle(stroke: Self.ramp, extra: ##", "strokeAlignment": "outer""##)
        #expect(content.contains(##"inset: "-8px","##))
        #expect(content.contains(##"borderWidth: "8px","##))
        #expect(!content.contains("padding:"))
        #expect(content.contains("#FF0000 8px, #0000FF calc(100% - 8px))"))
    }

    @Test("A middle stop keeps its place on the node box")
    func middleStopRemapped() throws {
        let stroke = """
        {"type": "gradient", "gradientType": "linear", "rotation": 270,
         "colors": [{"color": "#FF0000", "position": 0}, {"color": "#00FF00", "position": 0.25},
                    {"color": "#0000FF", "position": 1}]}
        """
        let content = try rectangle(stroke: stroke)
        #expect(content.contains("#00FF00 calc(4px + (100% - 8px) * 0.25)"))
    }

    @Test("A vertical gradient pads along the vertical offsets")
    func verticalGradientRemapped() throws {
        let stroke = Self.ramp.replacingOccurrences(of: "270", with: "180")
        let content = try rectangle(
            stroke: stroke, width: ##"{"top": 4, "right": 16, "bottom": 24, "left": 8}"##
        )
        #expect(content.contains("linear-gradient(-180deg, #FF0000 2px, #0000FF calc(100% - 12px))"))
    }

    @Test("Per-side widths are centered by default, each side on its own")
    func perSideCentered() throws {
        let content = try rectangle(stroke: Self.ramp, width: ##"{"top": 4, "right": 16, "bottom": 24, "left": 8}"##)
        #expect(content.contains(##"inset: "-2px -8px -12px -4px","##))
        #expect(content.contains(##"borderWidth: "2px 8px 12px 4px","##))
        #expect(content.contains(##"padding: "2px 8px 12px 4px","##))
        #expect(content.contains("#FF0000 4px, #0000FF calc(100% - 8px))"))
        #expect(!content.contains("borderTop"))
    }

    @Test("The overlay's corners grow by the outset, so the ring hugs the node's radius")
    func roundedCorners() throws {
        let content = try rectangle(stroke: Self.ramp, extra: ##", "cornerRadius": 12"##)
        #expect(content.contains("borderRadius: 16,"))
    }

    @Test("A CSS ellipse's overlay is an ellipse too")
    func ellipseOverlay() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Ell01", "name": "Dot", "width": 200, "height": 120,
         "stroke": \(Self.ramp), "strokeWidth": 8}
        """)
        #expect(content.contains(##"aria-hidden="true""##))
        #expect(content.components(separatedBy: ##"borderRadius: "50%","##).count == 3)
    }

    @Test("Stacked stroke paints become layers, top first")
    func stackedStroke() throws {
        let content = try rectangle(stroke: "[\"#00FF00\", \(Self.ramp)]", extra: ##", "strokeAlignment": "inner""##)
        #expect(content.contains(
            ##"backgroundImage: "linear-gradient(-270deg, #FF0000 0%, #0000FF 100%), linear-gradient(#00FF00, #00FF00)","##
        ))
        #expect(content.contains(##"backgroundOrigin: "border-box, border-box","##))
    }

    @Test("A blended stroke layer blends against the layers beneath it")
    func blendedLayer() throws {
        let blended = Self.ramp.replacingOccurrences(of: "\"linear\",", with: "\"linear\", \"blendMode\": \"multiply\",")
        let content = try rectangle(stroke: "[\"#00FF00\", \(blended)]", extra: ##", "strokeAlignment": "inner""##)
        #expect(content.contains(##"backgroundBlendMode: "multiply, normal","##))
    }

    @Test("A lone blended solid goes through the overlay so its blend mode applies")
    func blendedSolid() throws {
        let content = try rectangle(stroke: ##"{"type": "color", "color": "#FF0000", "blendMode": "multiply"}"##)
        #expect(content.contains(##"backgroundImage: "linear-gradient(#FF0000, #FF0000)","##))
        #expect(content.contains(##"mixBlendMode: "multiply","##))
        #expect(!content.contains("boxShadow"))
    }

    @Test("An image stroke is laid out over the node box and drawn nowhere else")
    func imageStroke() throws {
        let content = try rectangle(
            stroke: ##"{"type": "image", "url": "./images/uv.png", "mode": "fit"}"##,
            extra: ##", "strokeAlignment": "outer""##
        )
        #expect(content.contains(##"backgroundImage: "url('./images/uv.png')","##))
        #expect(content.contains(##"backgroundSize: "contain","##))
        #expect(content.contains(##"backgroundOrigin: "padding-box","##))
    }

    @Test("A mesh stroke paints its baked raster over the node box")
    func meshStroke() throws {
        let mesh = """
        {"type": "mesh_gradient", "columns": 2, "rows": 2,
         "colors": ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF"], "points": [[0, 0], [1, 0], [0, 1], [1, 1]]}
        """
        let content = try rectangle(stroke: mesh)
        #expect(content.contains(##"backgroundImage: "url('data:image/png;base64,"##))
        #expect(content.contains(##"backgroundOrigin: "padding-box","##))
    }

    @Test("A radial stroke keeps its ellipse on the node box")
    func radialStroke() throws {
        let stroke = """
        {"type": "gradient", "gradientType": "radial",
         "colors": [{"color": "#FFFF00", "position": 0}, {"color": "#00FFFF", "position": 1}]}
        """
        let content = try rectangle(stroke: stroke)
        #expect(content.contains(
            "radial-gradient(calc((100% - 8px) * 0.5) calc((100% - 8px) * 0.5), #FFFF00 0%, #00FFFF 100%)"
        ))
    }

    @Test("A frame's painted stroke sits beneath its children")
    func frameStrokeBeneathChildren() throws {
        let content = try card(child: """
        {"type": "frame", "id": "Inner", "name": "Panel", "width": 200, "height": 120,
         "stroke": \(Self.ramp), "strokeWidth": 8,
         "children": [{"type": "rectangle", "id": "Kid01", "width": 10, "height": 10, "fill": "#FFFFFF"}]}
        """)
        #expect(content.contains(##"className="flex relative""##))
        #expect(content.contains(##"isolation: "isolate","##))
        #expect(content.contains("zIndex: -1,"))
        let overlay = try #require(content.range(of: ##"aria-hidden="true""##))
        let kid = try #require(content.range(of: ##"backgroundColor: "#FFFFFF""##))
        #expect(overlay.lowerBound < kid.lowerBound)
    }
}
