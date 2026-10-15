import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Draws one stroked node on a transparent 200 × 120 canvas, for the dashed-stroke tests.
enum PenStrokeDashRendering {
    /// The canvas every drawing is made on.
    static let canvas = CGSize(width: 200, height: 120)

    /// The canvas with `node` — the JSON of one node — drawn on it, laid out.
    static func grid(_ node: String) throws -> PixelGrid {
        let document = try PenParser.parse(#"{"version": "2.19", "children": ["# + node + "]}")
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: canvas))
        return try #require(PixelGrid(image))
    }

    /// The bytes of a 100 × 60 rectangle at 20, 20 stroked 4 pt red, with `woodcase` as
    /// its `metadata.woodcase` keys.
    static func pixels(woodcase: String) throws -> Data {
        let document = try PenParser.parse("""
        {"version": "2.19", "children": [
          {"type": "rectangle", "id": "r", "x": 20, "y": 20, "width": 100, "height": 60, "stroke": "#FF0000",
           "strokeWidth": 4, "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
        ]}
        """)
        let image = try #require(PenRenderer.render(document, layoutRects: PenLayoutEngine.layout(document), size: canvas))
        return try #require(image.dataProvider?.data as Data?)
    }
}
