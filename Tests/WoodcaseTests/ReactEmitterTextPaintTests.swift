//
//  ReactEmitterTextPaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter paints a text node whose fills are more than one plain colour:
/// every enabled fill becomes a background layer over the text's own box, shown only
/// through the glyphs with `background-clip: text` — Pen's domain for a text paint is the
/// node box (`project/2026-09-26-text-and-stroke-fills.md`, finding 1).
struct ReactEmitterTextPaintTests {
    // MARK: - Helpers

    /// The emitted `Card` component, whose one child is a text node carrying `fill`.
    private func card(fill: String, text extra: String = ##", "textGrowth": "fixed-width", "width": 400"##) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "themes": {"mode": ["light", "dark"]},
         "variables": {"ink": {"type": "color", "value": [
           {"value": "#FF0000", "theme": {"mode": "light"}}, {"value": "#00FFFF", "theme": {"mode": "dark"}}]}},
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "text", "id": "Lbl01", "name": "Label", "content": "Hello",
             "fill": \(fill)\(extra)}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    private static let ramp = """
    {"type": "gradient", "gradientType": "linear", "rotation": 270,
     "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}
    """

    private static let clipDeclarations = [
        ##"backgroundClip: "text","##,
        ##"WebkitBackgroundClip: "text","##,
        ##"WebkitTextFillColor: "transparent","##,
        ##"color: "transparent","##,
    ]

    // MARK: - The plain-colour route

    /// Green on its first run: it pins today's output, which the change must keep.
    @Test("A lone solid colour stays a plain color declaration")
    func loneSolidStaysColor() throws {
        let content = try card(fill: "\"#123456\"")
        #expect(content.contains(##"color: "#123456","##))
        #expect(!content.contains("backgroundClip"))
    }

    @Test("A lone solid colour with a blend mode blends the text element")
    func blendedSolidBlendsElement() throws {
        let content = try card(fill: ##"{"type": "color", "color": "#123456", "blendMode": "multiply"}"##)
        #expect(content.contains(##"color: "#123456","##))
        #expect(content.contains(##"mixBlendMode: "multiply","##))
        #expect(!content.contains("backgroundClip"))
    }

    // MARK: - The painted route

    @Test("A linear gradient paints the glyphs through background-clip: text")
    func gradientClipsToText() throws {
        let content = try card(fill: Self.ramp)
        #expect(content.contains(##"backgroundImage: "linear-gradient(-270deg, #FF0000 0%, #0000FF 100%)","##))
        #expect(content.contains(##"backgroundSize: "100% 100%","##))
        #expect(content.contains(##"backgroundRepeat: "no-repeat","##))
        for declaration in Self.clipDeclarations {
            #expect(content.contains(declaration), "missing \(declaration)")
        }
    }

    @Test("Stacked fills become layers, top fill first, a solid as a flat gradient")
    func stackBecomesLayers() throws {
        let content = try card(fill: "[\"#00FF00\", \(Self.ramp)]")
        #expect(content.contains(
            ##"backgroundImage: "linear-gradient(-270deg, #FF0000 0%, #0000FF 100%), linear-gradient(#00FF00, #00FF00)","##
        ))
        #expect(!content.contains("backgroundBlendMode"))
    }

    @Test("Two stacked solids composite both, the top one first")
    func twoSolidsCompositeBoth() throws {
        let content = try card(fill: ##"["#F0F0F0", "#00000080"]"##)
        #expect(content.contains(
            ##"backgroundImage: "linear-gradient(#00000080, #00000080), linear-gradient(#F0F0F0, #F0F0F0)","##
        ))
        #expect(!content.contains(##"color: "#F0F0F0""##))
    }

    @Test("Fill blend modes become background-blend-mode, one per layer")
    func stackBlendModes() throws {
        let blended = Self.ramp.replacingOccurrences(of: "\"linear\",", with: "\"linear\", \"blendMode\": \"multiply\",")
        let content = try card(fill: "[\"#00FF00\", \(blended)]")
        #expect(content.contains(##"backgroundBlendMode: "multiply, normal","##))
    }

    @Test("A lone blended gradient blends the text element")
    func loneBlendedGradient() throws {
        let blended = Self.ramp.replacingOccurrences(of: "\"linear\",", with: "\"linear\", \"blendMode\": \"screen\",")
        let content = try card(fill: blended)
        #expect(content.contains(##"mixBlendMode: "screen","##))
        #expect(!content.contains("backgroundBlendMode"))
    }

    @Test("Image fills size their layer by mode, the others fill the box")
    func imageModesSizeLayers() throws {
        let image = ##"{"type": "image", "url": "./images/uv.png", "mode": "fit"}"##
        let content = try card(fill: "[\(Self.ramp), \(image)]")
        #expect(content.contains(
            ##"backgroundImage: "url('./images/uv.png'), linear-gradient(-270deg, #FF0000 0%, #0000FF 100%)","##
        ))
        #expect(content.contains(##"backgroundSize: "contain, 100% 100%","##))
        #expect(content.contains(##"backgroundPosition: "center","##))
    }

    @Test("A variable colour in a stack is a flat gradient of the variable")
    func variableSolidLayer() throws {
        let content = try card(fill: "[\"$ink\", \(Self.ramp)]")
        #expect(content.contains("linear-gradient(var(--ink), var(--ink))"))
    }

    @Test("A mesh gradient paints the text with its baked raster")
    func meshOnText() throws {
        let mesh = """
        {"type": "mesh_gradient", "columns": 2, "rows": 2,
         "colors": ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF"], "points": [[0, 0], [1, 0], [0, 1], [1, 1]]}
        """
        let content = try card(fill: mesh)
        #expect(content.contains(##"backgroundImage: "url('data:image/png;base64,"##))
        #expect(content.contains(##"backgroundClip: "text","##))
    }

    @Test("A shader alone paints nothing, as on shapes")
    func shaderAlonePaintsNothing() throws {
        // A shader is never emitted, and must not clip the text to an empty background.
        // Writing no colour at all used to leave the glyphs the page's black, which is not
        // nothing; they are transparent, as the Core Graphics renderer leaves them.
        let content = try card(fill: ##"{"type": "shader", "url": "./shaders/uv.frag"}"##)
        #expect(!content.contains("backgroundClip"))
        #expect(content.contains(##"color: "transparent","##))
    }

    @Test("A gradient's opacity is baked into its stops' alpha, as Pen's own export does")
    func gradientOpacityBaked() throws {
        let fill = """
        {"type": "gradient", "gradientType": "linear", "rotation": 270, "opacity": 0.5,
         "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FFCC", "position": 0.5},
                    {"color": "#0F0", "position": 0.75}, {"color": "$ink", "position": 1}]}
        """
        let content = try card(fill: fill)
        #expect(content.contains(
            "linear-gradient(-270deg, #FF000080 0%, #0000FF66 50%, #00FF0080 75%, color-mix(in srgb, var(--ink) 50%, transparent) 100%)"
        ))
    }

    @Test("Auto-width painted text sizes to its content, so the paint's box is the text's")
    func autoWidthFitsContent() throws {
        let content = try card(fill: Self.ramp, text: "")
        #expect(content.contains(##"width: "fit-content","##))
    }

    @Test("Fixed-width painted text keeps its width")
    func fixedWidthKeepsWidth() throws {
        let content = try card(fill: Self.ramp)
        #expect(content.contains("width: 400,"))
        #expect(!content.contains("fit-content"))
    }
}
