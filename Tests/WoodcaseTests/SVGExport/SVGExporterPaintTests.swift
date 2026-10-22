#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// How an SVG export writes fills, strokes, opacity and blend modes.
    struct SVGExporterPaintTests {
        private typealias Fixture = SVGExportFixture

        /// One 100×60 rectangle with `keys` spliced into it.
        private func rect(_ keys: String) throws -> XMLDocument {
            let fixture = try Fixture("""
            [{"type": "rectangle", "id": "r", "width": 100, "height": 60, \(keys)}]
            """)
            return try #require(try fixture.svg(["r"], imageProvider: { _ in Fixture.redImage }))
        }

        @Test("A solid fill is the path's fill color; a translucent one adds fill-opacity")
        func solidFill() throws {
            let opaque = try Fixture.elements("path", in: rect(##""fill": "#FF0000""##))
            #expect(opaque.count == 1)
            #expect(opaque.first.flatMap { Fixture.attribute("fill", of: $0) } == "#ff0000")
            #expect(opaque.first.flatMap { Fixture.attribute("fill-opacity", of: $0) } == nil)

            let translucent = try Fixture.elements("path", in: rect(##""fill": "#FF000080""##))
            #expect(translucent.first.flatMap { Fixture.attribute("fill-opacity", of: $0) } == "0.502")
        }

        @Test("Stacked fills draw one element each, bottom to top")
        func stackedFills() throws {
            let paths = try Fixture.elements("path", in: rect(##""fill": ["#FF0000", "#0000FF80"]"##))
            #expect(paths.compactMap { Fixture.attribute("fill", of: $0) } == ["#ff0000", "#0000ff"])
        }

        @Test("A linear gradient is a userSpaceOnUse gradient laid over the box, with its stops")
        func linearGradient() throws {
            let xml = try rect("""
            "fill": {"type": "gradient", "gradientType": "linear",
                     "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF80", "position": 1}]}
            """)
            let gradient = try #require(Fixture.elements("linearGradient", in: xml).first)
            #expect(Fixture.attribute("gradientUnits", of: gradient) == "userSpaceOnUse")
            #expect(Fixture.attribute("gradientTransform", of: gradient) != nil)
            let stops = try Fixture.elements("stop", in: xml)
            #expect(stops.compactMap { Fixture.attribute("stop-color", of: $0) } == ["#ff0000", "#0000ff"])
            #expect(stops.last.flatMap { Fixture.attribute("stop-opacity", of: $0) } == "0.502")
            let id = try #require(Fixture.attribute("id", of: gradient))
            let path = try #require(Fixture.elements("path", in: xml).first)
            #expect(Fixture.attribute("fill", of: path) == "url(#\(id))")
        }

        @Test("A radial gradient is a radialGradient")
        func radialGradient() throws {
            let xml = try rect("""
            "fill": {"type": "gradient", "gradientType": "radial",
                     "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}
            """)
            #expect(try Fixture.elements("radialGradient", in: xml).count == 1)
        }

        @Test("An angular gradient, which SVG cannot draw, is embedded as an image of its paint")
        func angularGradientFallsBackToAnImage() throws {
            let xml = try rect("""
            "fill": {"type": "gradient", "gradientType": "angular",
                     "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}
            """)
            let image = try #require(Fixture.elements("image", in: xml).first)
            #expect(Fixture.attribute("href", of: image)?.hasPrefix("data:image/png;base64,") == true)
        }

        @Test("An image fill embeds its pixels as PNG data, clipped to the shape")
        func imageFill() throws {
            let xml = try rect(##""fill": {"type": "image", "url": "red.png", "mode": "stretch"}"##)
            let image = try #require(Fixture.elements("image", in: xml).first)
            #expect(Fixture.attribute("href", of: image)?.hasPrefix("data:image/png;base64,") == true)
            #expect(try Fixture.elements("clipPath", in: xml).count >= 1)
        }

        @Test("A centered stroke is an SVG stroke at its own width")
        func centeredStroke() throws {
            let xml = try rect(##""stroke": "#000000", "strokeWidth": 4, "strokeAlignment": "center""##)
            let stroked = try #require(Fixture.elements("path", in: xml).first { Fixture.attribute("stroke", of: $0) != nil })
            #expect(Fixture.attribute("stroke", of: stroked) == "#000000")
            #expect(Fixture.attribute("stroke-width", of: stroked) == "4")
            #expect(Fixture.attribute("fill", of: stroked) == "none")
            #expect(Fixture.attribute("clip-path", of: stroked) == nil)
            #expect(Fixture.attribute("mask", of: stroked) == nil)
        }

        @Test("An inner stroke is twice as wide, clipped to the shape")
        func innerStroke() throws {
            let xml = try rect(##""stroke": "#000000", "strokeWidth": 4, "strokeAlignment": "inner""##)
            let stroked = try #require(Fixture.elements("path", in: xml).first { Fixture.attribute("stroke", of: $0) != nil })
            #expect(Fixture.attribute("stroke-width", of: stroked) == "8")
            #expect(Fixture.attribute("clip-path", of: stroked) != nil)
        }

        @Test("An outer stroke is twice as wide, masked to outside the shape")
        func outerStroke() throws {
            let xml = try rect(##""stroke": "#000000", "strokeWidth": 4, "strokeAlignment": "outer""##)
            let stroked = try #require(Fixture.elements("path", in: xml).first { Fixture.attribute("stroke", of: $0) != nil })
            #expect(Fixture.attribute("stroke-width", of: stroked) == "8")
            #expect(Fixture.attribute("mask", of: stroked) != nil)
            #expect(try Fixture.elements("mask", in: xml).count == 1)
        }

        @Test("A per-side stroke is its ring, filled even-odd")
        func perSideStroke() throws {
            let xml = try rect(##""stroke": "#000000", "strokeWidth": {"top": 4, "right": 0, "bottom": 2, "left": 0}"##)
            let ring = try #require(Fixture.elements("path", in: xml).first { Fixture.attribute("fill-rule", of: $0) == "evenodd" })
            #expect(Fixture.attribute("fill", of: ring) == "#000000")
        }

        @Test("A node's opacity is its group's opacity")
        func opacity() throws {
            let groups = try Fixture.elements("g", in: rect(##""fill": "#FF0000", "opacity": 0.5"##))
            #expect(groups.contains { Fixture.attribute("opacity", of: $0) == "0.5" })
        }

        @Test("A node's blend mode is its group's mix-blend-mode; a fill's is its element's")
        func blendModes() throws {
            let node = try Fixture.elements("g", in: rect(##""fill": "#FF0000", "blendMode": "multiply""##))
            #expect(node.contains { Fixture.attribute("style", of: $0) == "mix-blend-mode:multiply" })

            let fill = try Fixture.elements("path", in: rect(##""fill": {"type": "color", "color": "#FF0000", "blendMode": "hardLight"}"##))
            #expect(fill.first.flatMap { Fixture.attribute("style", of: $0) } == "mix-blend-mode:hard-light")
        }

        /// Linear burn is `SVGExporterLinearBurnTests`'.
        @Test("Linear dodge is plus-lighter, a true add")
        func linearModes() throws {
            let dodge = try Fixture.elements("g", in: rect(##""fill": "#FF0000", "blendMode": "linearDodge""##))
            #expect(dodge.contains { Fixture.attribute("style", of: $0) == "mix-blend-mode:plus-lighter" })
        }

        /// A paint blends only within its node's paints (Ben's reading-1 ruling, 2026-10-20),
        /// so a node whose paints blend draws them in an isolated group of their own; its
        /// outer shadow stays outside it.
        @Test("Blended paints draw in an isolated group, and only blended ones")
        func blendedPaintsIsolate() throws {
            let xml = try rect(##"""
            "fill": ["#FFFF00", {"type": "color", "color": "#0000FF", "blendMode": "multiply"}],
            "effect": {"type": "shadow", "shadowType": "outer", "offset": {"x": 4, "y": 4}, "blur": 0, "color": "#000000"}
            """##)
            let isolated = try Fixture.elements("g", in: xml).filter { Fixture.attribute("style", of: $0) == "isolation:isolate" }
            let group = try #require(isolated.first)
            #expect(isolated.count == 1)
            let paths = (group.children ?? []).compactMap { $0 as? XMLElement }
            #expect(paths.compactMap { Fixture.attribute("fill", of: $0) } == ["#ffff00", "#0000ff"])

            let plain = try Fixture.elements("g", in: rect(##""fill": ["#FFFF00", "#0000FF80"]"##))
            #expect(!plain.contains { Fixture.attribute("style", of: $0) == "isolation:isolate" })
        }
    }

#endif
