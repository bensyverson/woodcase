#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// A dashed stroke in an SVG export: `stroke-dasharray` and `stroke-dashoffset` on the
    /// stroked outline, which starts where the CG renderer's does, so the dashes land alike.
    struct SVGExporterStrokeDashTests {
        private typealias Fixture = SVGExportFixture

        private func svg(_ keys: String, paint: String = ##""#FF0000""##) throws -> XMLDocument {
            let fixture = try Fixture("""
            [{"id": "n", \(keys), "stroke": \(paint), "strokeWidth": 2,
              "metadata": {"type": "woodcase", "woodcase": {"strokeDash": [8, 4], "strokeDashOffset": 3}}}]
            """)
            return try #require(try fixture.svg(["n"]))
        }

        @Test("A dashed stroke writes its dash and offset",
              arguments: [
                  #""type": "rectangle", "width": 80, "height": 40, "cornerRadius": 8"#,
                  #""type": "ellipse", "width": 80, "height": 40"#,
                  #""type": "path", "width": 80, "height": 40, "geometry": "M0 0 L80 0 L80 40""#,
                  #""type": "line", "width": 80, "height": 0"#,
              ])
        func dashed(keys: String) throws {
            let xml = try svg(keys)
            let stroked = try Fixture.elements("path", in: xml).filter { Fixture.attribute("stroke", of: $0) != nil }
            let path = try #require(stroked.first)
            #expect(Fixture.attribute("stroke-dasharray", of: path) == "8 4")
            #expect(Fixture.attribute("stroke-dashoffset", of: path) == "3")
        }

        @Test("A rounded rectangle's stroked outline starts past the top-left radius")
        func roundedRectangleStart() throws {
            let xml = try svg(#""type": "rectangle", "width": 80, "height": 40, "cornerRadius": 8"#)
            let stroked = try Fixture.elements("path", in: xml).filter { Fixture.attribute("stroke", of: $0) != nil }
            let d = try #require(stroked.first.flatMap { Fixture.attribute("d", of: $0) })
            #expect(d.hasPrefix("M8 0L72 0"), "\(d)")
        }
    }

#endif
