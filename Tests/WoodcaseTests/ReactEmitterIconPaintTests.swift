//
//  ReactEmitterIconPaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What the React emitter writes for an icon painted with something a colour cannot carry.
///
/// Pen draws an icon's gradient or image fill through the glyph, laid out over the node's
/// box (`render-text-unfilled.pen`, the `gradient` and `image` boards). Every icon library
/// the emitter imports draws an SVG, so the paint is an SVG paint server in the icon's own
/// user space — its `viewBox` is the node's box — written into a hidden sibling `<svg>`
/// and named by the attribute that library paints its glyph with: `stroke` for lucide and
/// feather, `fill` for phosphor and Material Symbols.
struct ReactEmitterIconPaintTests {
    // MARK: - Helpers

    /// The emitted `Card` component, whose one child is an icon of `library` and `name`
    /// carrying `fill`.
    private func icon(fill: String, library: String = "lucide", name: String = "square") throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "icon", "id": "Ic001", "name": "Glyph", "icon": "\(name)", "library": "\(library)",
                         "width": 24, "height": 24, "fill": \(fill)}]}]}
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
    private static let image = ##"{"type": "image", "url": "./images/uv.png", "mode": "stretch"}"##
    private static let shader = ##"{"type": "shader", "url": "./uv.frag"}"##

    /// The id a `url(#…)` paint in `content` names, and whether that id is defined there.
    private func paintServer(in content: String, attribute: String) throws -> (id: String, defined: Bool) {
        let match = try #require(try content.firstMatch(of: Regex("\(attribute)=\"url\\(#([a-z0-9-]+)\\)\"")))
        let id = try #require(match.output[1].substring.map(String.init))
        return (id, content.contains("id=\"\(id)\""))
    }

    // MARK: - Gradient

    @Test("A lucide icon's gradient is a paint server its stroke names, defined beside it")
    func lucideGradient() throws {
        let content = try icon(fill: Self.ramp)
        let server = try paintServer(in: content, attribute: "stroke")
        #expect(server.defined, "\(content)")
        #expect(content.contains("<linearGradient"))
        #expect(content.contains(##"gradientUnits="userSpaceOnUse""##))
        #expect(!content.contains("color="), "\(content)")
    }

    @Test("The gradient spans the icon's viewBox, which is the node's box", arguments: [
        ("lucide", "square", "stroke", " 12 12)"),
        ("feather", "square", "stroke", " 12 12)"),
        ("phosphor", "square", "fill", " 128 128)"),
        ("Material Symbols Outlined", "home", "fill", " 480 -480)"),
    ])
    func gradientDomain(library: String, name: String, attribute: String, centre: String) throws {
        let content = try icon(fill: Self.ramp, library: library, name: name)
        let server = try paintServer(in: content, attribute: attribute)
        #expect(server.defined, "\(library): \(content)")
        let transform = try #require(content.firstMatch(of: /gradientTransform="(matrix\([^)]*\))"/)?.output.1)
        #expect(transform.hasSuffix(centre), "\(library): \(transform)")
    }

    @Test("The paint server sits in a hidden SVG of no size, so it takes no room in the layout")
    func hiddenDefinitions() throws {
        let content = try icon(fill: Self.ramp)
        #expect(content.contains(##"<svg width={0} height={0} aria-hidden="true" style={{ position: "absolute" }}>"##), "\(content)")
        #expect(content.contains("<>"))
        #expect(content.contains("</>"))
    }

    // MARK: - Image

    @Test("An icon's image fill is a pattern holding the image once over the icon's box")
    func imageFill() throws {
        let content = try icon(fill: Self.image)
        let server = try paintServer(in: content, attribute: "stroke")
        #expect(server.defined, "\(content)")
        #expect(content.contains("<pattern"))
        #expect(content.contains(##"<image href="./images/uv.png""##))
    }

    // MARK: - Choosing the paint

    @Test("A gradient over a colour paints the gradient: Pen paints the top fill over the other")
    func gradientOverColour() throws {
        let content = try icon(fill: "[\"#00FF00\", \(Self.ramp)]")
        _ = try paintServer(in: content, attribute: "stroke")
        #expect(!content.contains("#00FF00"), "\(content)")
    }

    @Test("A colour over a gradient stays a colour")
    func colourOverGradient() throws {
        let content = try icon(fill: "[\(Self.ramp), \"#00FF00\"]")
        #expect(content.contains(##"color="#00FF00""##), "\(content)")
        #expect(!content.contains("<linearGradient"))
    }

    @Test("A disabled gradient over a colour paints the colour")
    func disabledGradientOverColour() throws {
        let disabled = Self.ramp.replacingOccurrences(of: "\"rotation\": 270", with: "\"rotation\": 270, \"enabled\": false")
        let content = try icon(fill: "[\"#00FF00\", \(disabled)]")
        #expect(content.contains(##"color="#00FF00""##), "\(content)")
        #expect(!content.contains("<linearGradient"))
    }

    // MARK: - Shader

    @Test("A shader-only icon draws nothing rather than the page's black")
    func shaderOnly() throws {
        let content = try icon(fill: Self.shader)
        #expect(content.contains(##"color="transparent""##), "\(content)")
    }
}
