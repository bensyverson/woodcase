#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// A node's miter limit and shadow spreads in an SVG export (leaf zRp9CO): the limit as
    /// `stroke-miterlimit`, Pen's 4 unless `metadata.woodcase.strokeMiterLimit` says
    /// otherwise; an outer shadow's spread as the node's path grown along its outline, as the
    /// CG renderer grows it, and an inner shadow's as an `feMorphology` of its inverse.
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

        @Test("A spread outer shadow is cast by the silhouette's path grown, or shrunk, along its outline")
        func outerSpread() throws {
            for spread in [4, -3] {
                let xml = try svg(woodcase: #""shadowSpread": [{"effect": 0, "spread": \#(spread), "shadow": SHADOW}]"#)
                #expect(try Fixture.elements("feMorphology", in: xml).isEmpty, "grown as the CG renderer grows it, not by a square kernel")
                let filtered = try xml.nodes(forXPath: "//*[local-name()='path'][@filter]").compactMap { $0 as? XMLElement }
                let silhouette = try #require(filtered.first.flatMap { Fixture.attribute("d", of: $0) })
                let fill = try Fixture.elements("path", in: xml).first { Fixture.attribute("fill", of: $0) == "#FFFFFF" }
                #expect(silhouette != fill.flatMap { Fixture.attribute("d", of: $0) }, "spread \(spread) changes the outline")
                #expect(try Fixture.elements("mask", in: xml).count == 1, "knocked out under the ungrown silhouette")
            }
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
