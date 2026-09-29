//
//  ReactEmitterSVGAngularTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An angular gradient on a shape React draws as SVG — a polygon, a path, a line, an arc or
/// donut ellipse — whose fill or stroke SVG has no paint server for (leaf Mu4JsL,
/// `render-angular-shapes`): the gradient is a CSS `conic-gradient` in a `foreignObject`
/// over the node's box, grown past it for the stroke's overhang, clipped to the shape for
/// a fill and masked by the stroked shape for a stroke.
struct ReactEmitterSVGAngularTests {
    private func card(child: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    private static let angular = ##"""
    {"type": "gradient", "gradientType": "angular", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}
    """##

    @Test("A polygon's angular fill is a conic gradient clipped to the polygon")
    func polygonFill() throws {
        let content = try card(child: """
        {"type": "polygon", "id": "Poly1", "width": 180, "height": 140, "polygonCount": 6, "fill": \(Self.angular)}
        """)
        let clip = try #require(content.firstMatch(of: /<clipPath id="(wc-clip-[0-9a-f]{12})">/), "\(content)").output.1
        #expect(content.contains("<foreignObject"), "\(content)")
        #expect(content.contains(##"clipPath="url(#\##(clip))""##), "\(content)")
        #expect(content.contains("conic-gradient("), "\(content)")
        #expect(!content.contains(##"fill="url(#"##), "\(content)")
    }

    @Test("A path's angular stroke is a conic gradient masked by the stroked path")
    func pathStroke() throws {
        let content = try card(child: """
        {"type": "path", "id": "Path1", "width": 180, "height": 140, "geometry": "M0 140 L90 0 L180 140 Z",
         "fill": "#333333", "stroke": \(Self.angular), "strokeWidth": 12}
        """)
        let mask = try #require(content.firstMatch(of: /<mask id="(wc-stroke-[0-9a-f]{12})"[^>]*>/), "\(content)").output.1
        #expect(content.contains(##"<path d="M0 140 L90 0 L180 140 Z" fill="none" stroke="white" strokeWidth="12" />"##), "\(content)")
        #expect(content.contains(##"mask="url(#\##(mask))""##), "\(content)")
        #expect(content.contains("conic-gradient("), "\(content)")
        #expect(content.contains(##"fill="#333333""##), "\(content)")
    }

    @Test("Two angular layers on one stroke share one mask definition")
    func twoAngularStrokeLayers() throws {
        let content = try card(child: """
        {"type": "path", "id": "Path1", "width": 180, "height": 140, "geometry": "M0 140 L90 0 L180 140 Z",
         "stroke": [\(Self.angular), \(Self.angular)], "strokeWidth": 12}
        """)
        #expect(content.matches(of: /<mask id="wc-stroke-/).count == 1, "\(content)")
        #expect(content.matches(of: /conic-gradient\(/).count == 2, "\(content)")
    }

    @Test("An inner angular stroke is drawn twice as wide and clipped to the shape, as a solid inner one is")
    func innerStroke() throws {
        let content = try card(child: """
        {"type": "path", "id": "Path1", "width": 180, "height": 140, "geometry": "M0 140 L90 0 L180 140 Z",
         "stroke": \(Self.angular), "strokeWidth": 8, "strokeAlignment": "inner"}
        """)
        #expect(content.contains(##"stroke="white" strokeWidth="16""##), "\(content)")
        #expect(content.contains(##"clipPath="url(#wc-clip-"##), "\(content)")
        #expect(content.contains("<foreignObject"), "\(content)")
    }

    @Test("A line's angular stroke is masked by the stroked line")
    func lineStroke() throws {
        let content = try card(child: """
        {"type": "line", "id": "Line1", "width": 180, "height": 120, "stroke": \(Self.angular), "strokeWidth": 16}
        """)
        #expect(content.contains(##"<line x1="0" y1="0" x2="180" y2="120" fill="none" stroke="white" strokeWidth="16" />"##), "\(content)")
        #expect(content.contains("<foreignObject"), "\(content)")
        #expect(content.contains("conic-gradient("), "\(content)")
    }

    @Test("A donut's angular fill is clipped to the donut, even-odd")
    func donutFill() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Ell1", "width": 180, "height": 140, "innerRadius": 0.5, "fill": \(Self.angular)}
        """)
        #expect(content.contains("<foreignObject"), "\(content)")
        #expect(content.contains("conic-gradient("), "\(content)")
        #expect(content.contains(##"clipRule="evenodd""##), "\(content)")
    }

    @Test("The foreignObject covers the box grown by the stroke's overhang, its gradient filling it")
    func overhang() throws {
        let content = try card(child: """
        {"type": "polygon", "id": "Poly1", "width": 100, "height": 100, "polygonCount": 4,
         "stroke": \(Self.angular), "strokeWidth": 10}
        """)
        // A centered 10 pt stroke: an overhang of twice the drawn width plus one, as the paint servers use.
        #expect(content.contains(##"<foreignObject x="-21" y="-21" width="142" height="142""##), "\(content)")
        #expect(content.contains(##"width: "100%""##), "\(content)")
    }
}
