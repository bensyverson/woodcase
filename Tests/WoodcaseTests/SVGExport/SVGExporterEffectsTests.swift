#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// How an SVG export writes shadows and blurs: as SVG filters.
    struct SVGExporterEffectsTests {
        private typealias Fixture = SVGExportFixture

        /// One 80×80 rectangle with `effect` as its effect.
        private func rect(effect: String, extra: String = "") throws -> XMLDocument {
            let fixture = try Fixture("""
            [{"type": "rectangle", "id": "r", "width": 80, "height": 80, "fill": "#FFFFFF", \(extra)"effect": \(effect)}]
            """)
            return try #require(try fixture.svg(["r"]))
        }

        @Test("An outer shadow is a filter: blurred by half its blur, moved by its offset, in its color")
        func outerShadow() throws {
            let xml = try rect(effect: """
            {"type": "shadow", "shadowType": "outer", "blur": 8, "color": "#00000080", "offset": {"x": 4, "y": 6}}
            """)
            let blur = try #require(Fixture.elements("feGaussianBlur", in: xml).first)
            #expect(Fixture.attribute("stdDeviation", of: blur) == "4")
            let offset = try #require(Fixture.elements("feOffset", in: xml).first)
            #expect(Fixture.attribute("dx", of: offset) == "4")
            #expect(Fixture.attribute("dy", of: offset) == "6")
            let flood = try #require(Fixture.elements("feFlood", in: xml).first)
            #expect(Fixture.attribute("flood-color", of: flood) == "#000000")
            #expect(Fixture.attribute("flood-opacity", of: flood) == "0.502")
            let filter = try #require(Fixture.elements("filter", in: xml).first)
            let id = try #require(Fixture.attribute("id", of: filter))
            let users = try Fixture.elements("path", in: xml).filter { Fixture.attribute("filter", of: $0) == "url(#\(id))" }
            #expect(users.count == 1, "the silhouette casts it")
        }

        @Test("A shadow's offset turns with its node, as Pen casts it")
        func shadowOffsetTurnsWithNode() throws {
            let xml = try rect(
                effect: #"{"type": "shadow", "shadowType": "outer", "blur": 0, "offset": {"x": 10, "y": 0}}"#,
                extra: #""rotation": 90, "#
            )
            let offset = try #require(Fixture.elements("feOffset", in: xml).first)
            let dx = try #require(Fixture.attribute("dx", of: offset).flatMap(Double.init))
            let dy = try #require(Fixture.attribute("dy", of: offset).flatMap(Double.init))
            // The filter works in the node's own coordinates, which carry its turn: the
            // offset is written as authored and turns with the node on screen.
            #expect(abs(dx - 10) < 0.001)
            #expect(abs(dy) < 0.001)
        }

        @Test("An inner shadow is a filter on the shape, kept inside it")
        func innerShadow() throws {
            let xml = try rect(effect: """
            {"type": "shadow", "shadowType": "inner", "blur": 6, "color": "#00000060", "offset": {"x": 2, "y": 2}}
            """)
            #expect(try Fixture.elements("feGaussianBlur", in: xml).first.flatMap { Fixture.attribute("stdDeviation", of: $0) } == "3")
            let composites = try Fixture.elements("feComposite", in: xml).compactMap { Fixture.attribute("operator", of: $0) }
            #expect(composites.last == "in", "the shadow is kept where the shape is: \(composites)")
        }

        @Test("A layer blur blurs the node's group by half its radius")
        func layerBlur() throws {
            let xml = try rect(effect: #"{"type": "blur", "radius": 4}"#)
            let filter = try #require(Fixture.elements("filter", in: xml).first)
            let id = try #require(Fixture.attribute("id", of: filter))
            #expect(try Fixture.elements("feGaussianBlur", in: xml).first.flatMap { Fixture.attribute("stdDeviation", of: $0) } == "2")
            #expect(try Fixture.elements("g", in: xml).contains { Fixture.attribute("filter", of: $0) == "url(#\(id))" })
        }

        @Test("A disabled effect writes no filter")
        func disabledEffect() throws {
            let xml = try rect(effect: #"{"type": "blur", "radius": 4, "enabled": false}"#)
            #expect(try Fixture.elements("filter", in: xml).isEmpty)
        }
    }

#endif
