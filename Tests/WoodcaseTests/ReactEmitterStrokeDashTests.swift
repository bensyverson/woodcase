//
//  ReactEmitterStrokeDashTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A dashed stroke in emitted React: SVG's `stroke-dasharray` and `stroke-dashoffset` on
/// the shape's own SVG, and on an SVG stroke overlay for a box — a frame, a rectangle or a
/// CSS ellipse — whose CSS stroke cannot dash exactly (Penumbra's
/// `project/2026-10-14-feature-enhancements-plan.md` §1.3).
struct ReactEmitterStrokeDashTests {
    private static let dashed = #""metadata": {"type": "woodcase", "woodcase": {"strokeDash": [8, 4], "strokeDashOffset": 3}}"#

    /// The emitted `Card` component: a vertical frame holding `child`, given as JSON.
    private func card(child: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    private func expectDashed(_ content: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(content.contains(#"strokeDasharray="8 4""#), "\(content)", sourceLocation: sourceLocation)
        #expect(content.contains(#"strokeDashoffset="3""#), "\(content)", sourceLocation: sourceLocation)
    }

    @Test("A dashed rectangle's stroke is an SVG overlay, not a CSS box-shadow")
    func rectangle() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Rect1", "name": "Box", "width": 200, "height": 120, "cornerRadius": 12,
         "fill": "#FFFFFF", "stroke": "#FF0000", "strokeWidth": 2, \(Self.dashed)}
        """)
        expectDashed(content)
        #expect(!content.contains("0 0 0 1px #FF0000"), "the CSS stroke is not drawn too: \(content)")
        #expect(content.contains(#"d="M12 0 L188 0"#), "the overlay starts past the top-left corner: \(content)")
    }

    @Test("A dashed frame's stroke is an SVG overlay beside its children")
    func frame() throws {
        let content = try card(child: """
        {"type": "frame", "id": "Frm1", "name": "Panel", "width": 200, "height": 120, "layout": "none",
         "stroke": "#FF0000", "strokeWidth": 2, \(Self.dashed),
         "children": [{"type": "rectangle", "id": "Chip1", "name": "Chip", "width": 20, "height": 20, "fill": "#00FF00"}]}
        """)
        expectDashed(content)
        #expect(content.contains("#00FF00"), "the child is still drawn: \(content)")
    }

    @Test("A dashed ellipse, path, polygon and line dash their own SVG",
          arguments: [
              #""type": "ellipse", "width": 80, "height": 40"#,
              #""type": "path", "width": 80, "height": 40, "geometry": "M0 0 L80 0 L80 40""#,
              #""type": "polygon", "width": 80, "height": 80, "polygonCount": 5"#,
              #""type": "line", "width": 80, "height": 0"#,
          ])
    func svgShapes(keys: String) throws {
        let content = try card(child: """
        {\(keys), "id": "Shp1", "name": "Shape", "stroke": "#FF0000", "strokeWidth": 2, \(Self.dashed)}
        """)
        expectDashed(content)
    }
}
