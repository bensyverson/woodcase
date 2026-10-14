#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// How an SVG export writes text — real `<text>`, one `<tspan>` per run of each line —
    /// and the nodes it embeds as pictures instead.
    struct SVGExporterTextTests {
        private typealias Fixture = SVGExportFixture

        @Test("A text node is a <text> in its family, size and weight, with its content")
        func textElement() throws {
            TestFontRegistration.registerTestFonts()
            let fixture = try Fixture("""
            [{"type": "text", "id": "t", "content": "Hello World", "fontFamily": "Inter", "fontSize": 20,
              "fontWeight": "700", "fill": "#112233"}]
            """)
            let xml = try #require(try fixture.svg(["t"]))
            let text = try #require(Fixture.elements("text", in: xml).first)
            #expect(Fixture.attribute("fill", of: text) == "#112233")
            let spans = try Fixture.elements("tspan", in: xml)
            #expect(spans.compactMap(\.stringValue).joined() == "Hello World")
            let span = try #require(spans.first)
            #expect(Fixture.attribute("font-family", of: span) == "Inter")
            #expect(Fixture.attribute("font-size", of: span) == "20")
            #expect(Fixture.attribute("font-weight", of: span) == "700")
        }

        @Test("Each laid-out line is its own tspan, on its own baseline")
        func wrappedLines() throws {
            TestFontRegistration.registerTestFonts()
            let fixture = try Fixture("""
            [{"type": "text", "id": "t", "content": "one two three four five six", "fontFamily": "Inter",
              "fontSize": 16, "textGrowth": "fixed-width", "width": 60, "fill": "#000000"}]
            """)
            let xml = try #require(try fixture.svg(["t"]))
            let baselines = try Set(Fixture.elements("tspan", in: xml).compactMap { Fixture.attribute("y", of: $0) })
            #expect(baselines.count > 1)
        }

        @Test("Markup characters in content are escaped")
        func escaping() throws {
            let fixture = try Fixture("""
            [{"type": "text", "id": "t", "content": "a < b & \\"c\\"", "fontFamily": "Inter", "fontSize": 12, "fill": "#000000"}]
            """)
            let xml = try #require(try fixture.svg(["t"]))
            #expect(try Fixture.elements("tspan", in: xml).compactMap(\.stringValue).joined() == "a < b & \"c\"")
        }

        @Test("A gradient text paints its <text> with the gradient")
        func gradientText() throws {
            let fixture = try Fixture("""
            [{"type": "text", "id": "t", "content": "Ramp", "fontFamily": "Inter", "fontSize": 40,
              "fill": {"type": "gradient", "gradientType": "linear",
                       "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}}]
            """)
            let xml = try #require(try fixture.svg(["t"]))
            let id = try #require(Fixture.elements("linearGradient", in: xml).first.flatMap { Fixture.attribute("id", of: $0) })
            #expect(try Fixture.elements("text", in: xml).first.flatMap { Fixture.attribute("fill", of: $0) } == "url(#\(id))")
        }

        @Test("An icon is its glyph's outline, so it draws without the icon font installed")
        func iconIsOutlined() throws {
            let fixture = try Fixture("""
            [{"type": "icon", "id": "i", "library": "lucide", "icon": "heart",
              "width": 24, "height": 24, "fill": "#FF0000"}]
            """)
            let xml = try #require(try fixture.svg(["i"]))
            #expect(try Fixture.elements("text", in: xml).isEmpty)
            let glyph = try #require(Fixture.elements("path", in: xml).first)
            #expect(Fixture.attribute("fill", of: glyph) == "#ff0000")
            #expect((Fixture.attribute("d", of: glyph)?.count ?? 0) > 20)
        }

        @Test("A note, which SVG has no vocabulary for, is embedded as the CG renderer's picture of it")
        func noteFallsBackToAnImage() throws {
            let fixture = try Fixture("""
            [{"type": "note", "id": "n", "x": 0, "y": 0, "width": 200, "height": 120, "content": "Remember"}]
            """)
            let xml = try #require(try fixture.svg(["n"]))
            let image = try #require(Fixture.elements("image", in: xml).first)
            #expect(Fixture.attribute("href", of: image)?.hasPrefix("data:image/png;base64,") == true)
        }
    }

#endif
