//
//  ReactEmitterStrokeBandTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A box's stroke band as Pen draws it, measured on the `render-inner-sides`,
/// `render-unstroked-lines` and `render-stroke-bands` exports (leaf Mu4JsL): an inner
/// per-side stroke moves no child and paints beneath them, a line with no stroke paint
/// draws nothing, an outer stroke is a band even around a 0×0 box, and a node's outer
/// shadows are cast by its shape grown by the stroke's outer reach.
struct ReactEmitterStrokeBandTests {
    /// The emitted `Card` component: a vertical frame holding `child`, given as JSON.
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

    private static let sides = ##"{"top": 12, "right": 4, "bottom": 20, "left": 24}"##
    private static let shadow = ##""effect": {"type": "shadow", "shadowType": "outer", "color": "#FFFFFF", "offset": {"x": 10, "y": 10}, "blur": 8}"##

    // MARK: - Inner per-side strokes

    @Test("An inner per-side stroke is an overlay under the frame's children, not a border that moves them")
    func innerPerSideBeneathChildren() throws {
        let content = try card(child: """
        {"type": "frame", "id": "Box01", "name": "Box", "width": 200, "height": 140, "layout": "vertical",
         "stroke": "#FFFFFF", "strokeWidth": \(Self.sides), "strokeAlignment": "inner",
         "children": [{"type": "rectangle", "id": "Kid01", "width": 80, "height": 40, "fill": "#FF00FF"}]}
        """)
        #expect(!content.contains("borderTop"), "\(content)")
        #expect(!content.contains("borderLeft"), "\(content)")
        #expect(content.contains(##"padding: "12px 4px 20px 24px","##), "\(content)")
        #expect(content.contains("linear-gradient(#FFFFFF, #FFFFFF)"), "\(content)")
        #expect(content.contains("zIndex: -1,"), "\(content)")
        #expect(content.contains(##"isolation: "isolate""##), "\(content)")
    }

    @Test("A childless box's inner per-side stroke is an overlay too")
    func innerPerSideChildless() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Box01", "name": "Box", "width": 200, "height": 140,
         "stroke": "#FFFFFF", "strokeWidth": \(Self.sides), "strokeAlignment": "inner"}
        """)
        #expect(!content.contains("borderTop"), "\(content)")
        #expect(content.contains(##"padding: "12px 4px 20px 24px","##), "\(content)")
        #expect(!content.contains("zIndex"), "\(content)")
    }

    // MARK: - Lines with no stroke

    @Test("A line with no stroke paint draws nothing, whatever its width", arguments: [
        "", ##", "strokeWidth": 8"##, ##", "stroke": {"type": "color", "color": "#FF0000", "enabled": false}, "strokeWidth": 8"##,
    ])
    func unstrokedLine(keys: String) throws {
        let content = try card(child: ##"{"type": "line", "id": "Line1", "name": "Rule", "width": 180, "height": 100\##(keys)}"##)
        #expect(!content.contains("<line"), "\(content)")
        #expect(!content.contains("currentColor"), "\(content)")
        #expect(content.contains("<svg width={180} height={100}"), "\(content)")
    }

    @Test("A full-width line with no stroke paint draws no border and keeps its height")
    func unstrokedFullWidthLine() throws {
        let content = try card(child: ##"{"type": "line", "id": "Line1", "name": "Rule", "width": "fill_container", "height": 6, "strokeWidth": 6}"##)
        #expect(!content.contains("borderTop"), "\(content)")
        #expect(!content.contains("currentColor"), "\(content)")
        #expect(content.contains("height: 6,"), "\(content)")
    }

    // MARK: - Outer bands and the shadows they cast

    @Test("An outer stroke is a spread box-shadow on top of the node's shadows, which it grows by its width")
    func outerStrokeSpread() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Box01", "name": "Box", "width": 100, "height": 60, "cornerRadius": 10,
         "stroke": "#00FF00", "strokeWidth": 12, "strokeAlignment": "outer", \(Self.shadow)}
        """)
        #expect(content.contains(##"boxShadow: "0 0 0 12px #00FF00, 10px 10px 8px 12px #FFFFFF","##), "\(content)")
        #expect(!content.contains("outline"), "\(content)")
    }

    @Test("A centered stroke grows the node's shadows by half its width")
    func centeredStrokeSpread() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Box01", "name": "Box", "width": 100, "height": 60,
         "stroke": "#00FF00", "strokeWidth": 12, \(Self.shadow)}
        """)
        #expect(content.contains(##"boxShadow: "inset 0 0 0 6px #00FF00, 0 0 0 6px #00FF00, 10px 10px 8px 6px #FFFFFF","##), "\(content)")
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("An inner stroke leaves the node's shadows as they are")
    func innerStrokeNoSpread() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Box01", "name": "Box", "width": 100, "height": 60,
         "stroke": "#00FF00", "strokeWidth": 12, "strokeAlignment": "inner", \(Self.shadow)}
        """)
        #expect(content.contains(##"boxShadow: "inset 0 0 0 12px #00FF00, 10px 10px 8px #FFFFFF","##), "\(content)")
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("A stroke width with no stroke paint grows no shadow")
    func unpaintedStrokeNoSpread() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Box01", "name": "Box", "width": 100, "height": 60,
         "strokeWidth": 12, "strokeAlignment": "outer", \(Self.shadow)}
        """)
        #expect(content.contains(##"boxShadow: "10px 10px 8px #FFFFFF","##), "\(content)")
    }

    @Test("A 0×0 frame's outer stroke is a band about the point, and casts the shadow")
    func sizelessFrameBand() throws {
        let content = try card(child: """
        {"type": "frame", "id": "Box01", "name": "Box", "layout": "none", "fill": "#808080",
         "stroke": "#00FF00", "strokeWidth": 8, "strokeAlignment": "outer", \(Self.shadow)}
        """)
        #expect(content.contains("width: 0,"), "\(content)")
        #expect(content.contains(##"boxShadow: "0 0 0 8px #00FF00, 10px 10px 8px 8px #FFFFFF","##), "\(content)")
    }

    @Test("A blended shadow's layer is grown by the stroke too")
    func layeredShadowSpread() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Box01", "name": "Box", "width": 100, "height": 60,
         "stroke": "#00FF00", "strokeWidth": 12, "strokeAlignment": "outer",
         "effect": {"type": "shadow", "shadowType": "outer", "color": "#FFFFFF", "offset": {"x": 10, "y": 10}, "blur": 8, "blendMode": "multiply"}}
        """)
        #expect(content.contains(##"boxShadow: "10px 10px 8px 12px #FFFFFF","##), "\(content)")
    }
}
