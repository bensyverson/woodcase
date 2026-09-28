//
//  ReactEmitterPerSideShapeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A per-side stroke width on a shape without box sides, in emitted React.
///
/// Pen strokes an ellipse, a polygon, a path or a line with a per-side width as one
/// uniform stroke of the top width, the other sides ignored (`render-per-side-shapes.pen`;
/// finding F6 of `project/2026-09-27-fidelity-gaps.md`), so React writes that width.
struct ReactEmitterPerSideShapeTests {
    /// A shape of each kind React writes as SVG, as a JSON object missing only its stroke.
    static let svgShapes: [String] = ReactEmitterSVGFillTests.shapes + [
        ##"{"type": "line", "id": "Shp01", "name": "Shape", "width": 40, "height": 0"##,
    ]

    private static let perSide = ##""stroke": "#FF0000", "strokeWidth": {"top": 12, "right": 2, "bottom": 6, "left": 0}"##

    /// The emitted `Card` component holding `shape` closed with `keys`.
    private func card(shape: String, keys: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(shape), \(keys)}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    @Test("An SVG shape's solid per-side stroke is written at the top width", arguments: svgShapes)
    func solidSVG(shape: String) throws {
        let content = try card(shape: shape, keys: Self.perSide)
        #expect(content.contains(##"stroke="#FF0000" strokeWidth="12""##), "\(content)")
    }

    @Test("An SVG shape's painted per-side stroke is drawn at the top width, doubled when inside", arguments: Array(svgShapes.prefix(4)))
    func paintedSVG(shape: String) throws {
        let gradient = ##"{"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}"##
        let keys = ##""stroke": \##(gradient), "strokeWidth": {"top": 12, "left": 3}, "strokeAlignment": "inner""##
        let content = try card(shape: shape, keys: keys)
        #expect(content.contains(##"strokeWidth="24""##), "\(content)")
    }

    @Test("A plain ellipse's per-side stroke is the top width all round, not borders")
    func cssEllipse() throws {
        let ellipse = ##"{"type": "ellipse", "id": "Shp01", "name": "Shape", "width": 40, "height": 40"##
        let content = try card(shape: ellipse, keys: Self.perSide)
        // Centred, as Pen draws it: half the top width inside the edge, half outside.
        #expect(content.contains(##"boxShadow: "inset 0 0 0 6px #FF0000, 0 0 0 6px #FF0000""##), "\(content)")
        #expect(!content.contains("borderTop"), "\(content)")
        #expect(!content.contains("borderBottom"), "\(content)")
    }
}
