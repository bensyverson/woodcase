#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// A node's miter limit and shadow spreads in an SVG export (leaf zRp9CO): the limit as
    /// `stroke-miterlimit`, Pen's 4 unless `metadata.woodcase.strokeMiterLimit` says
    /// otherwise; a spread as an `feMorphology` that grows the shape a shadow is cast by.
    struct SVGExporterMiterAndSpreadTests {
        private typealias Fixture = SVGExportFixture

        private static let shadow = ##"{"type": "shadow", "blur": 4, "color": "#000000"}"##

        private func svg(woodcase: String, shadowType: String = "outer") throws -> XMLDocument {
            let shadow = Self.shadow.replacingOccurrences(of: #""blur""#, with: #""shadowType": "\#(shadowType)", "blur""#)
            let woodcaseKeys = woodcase.replacingOccurrences(of: "SHADOW", with: shadow)
            let fixture = try Fixture("""
            [{"id": "n", "type": "path", "width": 80, "height": 40, "geometry": "M0 0 L80 20 L0 40 Z",
              "fill": "#FFFFFF", "stroke": "#000000", "strokeWidth": 2, "effect": \(shadow),
              "metadata": {"type": "woodcase", "woodcase": {\(woodcaseKeys)}}}]
            """)
            return try #require(try fixture.svg(["n"]))
        }

        private func miterLimit(_ xml: XMLDocument) throws -> String? {
            let stroked = try Fixture.elements("path", in: xml).filter { Fixture.attribute("stroke", of: $0) != nil }
            let path = try #require(stroked.first)
            return Fixture.attribute("stroke-miterlimit", of: path)
        }

        @Test("A mitered stroke writes Pen's limit of 4, or the node's own")
        func miterLimitIsWritten() throws {
            #expect(try miterLimit(svg(woodcase: "")) == "4")
            #expect(try miterLimit(svg(woodcase: #""strokeMiterLimit": 10"#)) == "10")
        }

        @Test("A spread outer shadow dilates the silhouette; a negative one erodes it")
        func outerSpread() throws {
            let grown = try Fixture.elements("feMorphology", in: svg(woodcase: #""shadowSpread": [{"effect": 0, "spread": 4, "shadow": SHADOW}]"#))
            #expect(grown.count == 1)
            #expect(grown.first.flatMap { Fixture.attribute("operator", of: $0) } == "dilate")
            #expect(grown.first.flatMap { Fixture.attribute("radius", of: $0) } == "4")
            let shrunk = try Fixture.elements("feMorphology", in: svg(woodcase: #""shadowSpread": [{"effect": 0, "spread": -3, "shadow": SHADOW}]"#))
            #expect(shrunk.first.flatMap { Fixture.attribute("operator", of: $0) } == "erode")
        }

        @Test("A spread inner shadow dilates the inverse it is cast from")
        func innerSpread() throws {
            let xml = try svg(woodcase: #""shadowSpread": [{"effect": 0, "spread": 4, "shadow": SHADOW}]"#, shadowType: "inner")
            let grown = try Fixture.elements("feMorphology", in: xml)
            #expect(grown.first.flatMap { Fixture.attribute("in", of: $0) } == "inverse")
            #expect(grown.first.flatMap { Fixture.attribute("operator", of: $0) } == "dilate")
        }

        @Test("No spread, or a stale one, writes no morphology")
        func noOrStaleSpread() throws {
            #expect(try Fixture.elements("feMorphology", in: svg(woodcase: "")).isEmpty)
            let stale = #""shadowSpread": [{"effect": 0, "spread": 4, "shadow": {"type": "shadow", "blur": 9}}]"#
            #expect(try Fixture.elements("feMorphology", in: svg(woodcase: stale)).isEmpty)
        }
    }

#endif
