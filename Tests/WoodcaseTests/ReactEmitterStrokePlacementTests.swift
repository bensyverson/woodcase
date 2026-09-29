//
//  ReactEmitterStrokePlacementTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Where the emitted React puts a stroke relative to the node's edge, as Pen does: a
/// centered box stroke half inside and half outside, a center or outer per-side stroke
/// outside the box, a line's stroke centered on the line — none of it moving the layout —
/// and an ellipse's arc drawn from the renderer's own geometry.
struct ReactEmitterStrokePlacementTests {
    /// The emitted `Card` component: a vertical frame holding `child`, given as JSON.
    private func card(child: String, gap: String = "") throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical"\(gap),
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    /// A 200 × 120 rectangle stroked red with `width` and anything in `extra`.
    private func rectangle(width: String, extra: String = "") throws -> String {
        try card(child: """
        {"type": "rectangle", "id": "Rect1", "name": "Box", "width": 200, "height": 120,
         "stroke": "#FF0000", "strokeWidth": \(width)\(extra)}
        """)
    }

    // MARK: - Centered box strokes (50MfO5)

    @Test("A centered solid stroke is half an inset box-shadow and half an outer one")
    func centeredStraddlesTheEdge() throws {
        let content = try rectangle(width: "8")
        #expect(content.contains(##"boxShadow: "inset 0 0 0 4px #FF0000, 0 0 0 4px #FF0000","##), "\(content)")
        #expect(!content.contains("outline"), "\(content)")
    }

    @Test("A centered stroke of a variable width halves the variable")
    func centeredVariableWidth() throws {
        let content = try rectangle(width: "\"$w\"")
        #expect(content.contains(
            ##"boxShadow: "inset 0 0 0 calc(var(--w) * 0.5) #FF0000, 0 0 0 calc(var(--w) * 0.5) #FF0000","##
        ), "\(content)")
    }

    @Test("A stroke with no width is drawn at Pen's default of 1, centered")
    func defaultWidth() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "Rect1", "name": "Box", "width": 200, "height": 120, "stroke": "#FF0000"}
        """)
        #expect(content.contains(##"boxShadow: "inset 0 0 0 0.5px #FF0000, 0 0 0 0.5px #FF0000","##), "\(content)")
    }

    @Test("A CSS ellipse's centered stroke straddles its edge too")
    func centeredEllipse() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Ell01", "name": "Dot", "width": 200, "height": 120, "stroke": "#FF0000", "strokeWidth": 6}
        """)
        #expect(content.contains(##"boxShadow: "inset 0 0 0 3px #FF0000, 0 0 0 3px #FF0000","##), "\(content)")
    }

    /// The shadow spreads by the stroke's outer half since leaf Mu4JsL: Pen casts it from
    /// the shape grown by the stroke (`render-stroke-bands`).
    @Test("A stroke paints over the node's own shadows, so its box-shadows come first")
    func strokeAboveShadows() throws {
        let content = try rectangle(
            width: "8",
            extra: ##", "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 0, "y": 4}, "blur": 6}"##
        )
        #expect(content.contains(##"boxShadow: "inset 0 0 0 4px #FF0000, 0 0 0 4px #FF0000, 0px 4px 6px 4px #000000","##), "\(content)")
    }

    // MARK: - Per-side strokes (hPsLl7)

    private static let mixed = ##"{"top": 4, "right": 16, "bottom": 24, "left": 8}"##

    @Test("A centered solid per-side stroke is an overlay reaching half of each side past the box")
    func perSideCentered() throws {
        let content = try rectangle(width: Self.mixed)
        #expect(content.contains(##"aria-hidden="true""##), "\(content)")
        #expect(content.contains(##"inset: "-2px -8px -12px -4px","##), "\(content)")
        #expect(content.contains(##"borderWidth: "2px 8px 12px 4px","##), "\(content)")
        #expect(content.contains(##"padding: "2px 8px 12px 4px","##), "\(content)")
        #expect(content.contains("linear-gradient(#FF0000, #FF0000)"), "\(content)")
        #expect(!content.contains("borderTop"), "\(content)")
    }

    @Test("An outer solid per-side stroke is an overlay wholly outside the box")
    func perSideOuter() throws {
        let content = try rectangle(width: Self.mixed, extra: ##", "strokeAlignment": "outer""##)
        #expect(content.contains(##"inset: "-4px -16px -24px -8px","##), "\(content)")
        #expect(content.contains(##"borderWidth: "4px 16px 24px 8px","##), "\(content)")
        #expect(!content.contains("padding:"), "\(content)")
        #expect(!content.contains("borderTop"), "\(content)")
    }

    // MARK: - Lines (SctC0l)

    private func line(_ keys: String) throws -> String {
        try card(child: ##"{"type": "line", "id": "Line1", "name": "Rule", "width": 140, "height": 0, \##(keys)}"##)
    }

    @Test("A line's SVG is grown by half the stroke on every side and pulled back by margins, so the stroke centers on the line")
    func lineCenteredOnItsY() throws {
        let content = try line(##""stroke": "#FF0000", "strokeWidth": 12"##)
        #expect(content.contains(##"<svg width={152} height={12} viewBox="-6 -6 152 12" overflow="visible""##), "\(content)")
        #expect(content.contains("margin: -6,"), "\(content)")
        #expect(content.contains(##"<line x1="0" y1="0" x2="140" y2="0" stroke="#FF0000" strokeWidth="12" />"##), "\(content)")
    }

    @Test("A line runs from its box's top-left corner to its bottom-right, as the renderer draws it")
    func diagonalLine() throws {
        let content = try card(child: ##"{"type": "line", "id": "Line1", "name": "Rule", "width": 40, "height": 30, "stroke": "#FF0000", "strokeWidth": 2}"##)
        #expect(content.contains(##"<line x1="0" y1="0" x2="40" y2="30""##), "\(content)")
        #expect(content.contains(##"viewBox="-1 -1 42 32""##), "\(content)")
    }

    @Test("A line keeps its cap")
    func lineCap() throws {
        let content = try line(##""stroke": "#FF0000", "strokeWidth": 8, "strokeLinecap": "round""##)
        #expect(content.contains(##"strokeLinecap="round""##), "\(content)")
    }

    @Test("A full-width line's border straddles its y and takes no height")
    func fullWidthLineCentered() throws {
        let content = try card(child: ##"{"type": "line", "id": "Line1", "name": "Rule", "width": "fill_container", "height": 0, "stroke": "#FF0000", "strokeWidth": 4}"##)
        #expect(content.contains(##"borderTop: "4px solid #FF0000","##), "\(content)")
        #expect(content.contains("marginTop: -2,"), "\(content)")
        #expect(content.contains("marginBottom: -2,"), "\(content)")
    }

    // MARK: - Caps and joins on SVG shapes

    @Test("A path's stroke keeps its cap and join")
    func pathCapAndJoin() throws {
        let content = try card(child: """
        {"type": "path", "id": "Path1", "name": "Tick", "width": 120, "height": 80, "geometry": "M10 70l50-60 50 60",
         "stroke": "#0066CC", "strokeWidth": 16, "strokeLinecap": "square", "strokeLinejoin": "bevel"}
        """)
        #expect(content.contains(##"strokeLinecap="square" strokeLinejoin="bevel""##), "\(content)")
    }

    @Test("A painted path stroke keeps its cap and join")
    func paintedPathCapAndJoin() throws {
        let gradient = ##"{"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}"##
        let content = try card(child: """
        {"type": "path", "id": "Path1", "name": "Tick", "width": 120, "height": 80, "geometry": "M10 70l50-60 50 60",
         "stroke": \(gradient), "strokeWidth": 16, "strokeLinejoin": "round"}
        """)
        #expect(content.contains(##"strokeLinejoin="round""##), "\(content)")
    }

    @Test("A path its viewBox stretches keeps its stroke at its own width, as the renderer strokes the mapped outline")
    func stretchedPathStroke() throws {
        let content = try card(child: """
        {"type": "path", "id": "Path1", "name": "Tick", "width": 120, "height": 80, "geometry": "M10 70l50-60 50 60",
         "stroke": "#0066CC", "strokeWidth": 16}
        """)
        #expect(content.contains(##"strokeWidth="16" vectorEffect="non-scaling-stroke""##), "\(content)")
    }

    @Test("A path its viewBox does not scale needs no non-scaling stroke")
    func unscaledPathStroke() throws {
        let content = try card(child: """
        {"type": "path", "id": "Path1", "name": "Bar", "width": 150, "height": 40, "geometry": "M0 20l150 0",
         "stroke": "#333333", "strokeWidth": 20}
        """)
        #expect(!content.contains("vectorEffect"), "\(content)")
    }

    // MARK: - Arcs (hPsLl7)

    @Test("An arc donut is drawn from the renderer's outline, its sweep kept")
    func arcDonut() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Ell01", "name": "Arc", "width": 200, "height": 120, "fill": "#FFFFFF",
         "startAngle": 0, "sweepAngle": 90, "innerRadius": 0.5}
        """)
        #expect(content.contains(##"d="M200 60 A100 60 0 0 0 100 0 L100 30 A50 30 0 0 1 150 60 Z""##), "\(content)")
    }

    @Test("A pie slice is drawn from the renderer's outline")
    func pieSlice() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Ell01", "name": "Arc", "width": 200, "height": 120, "fill": "#FFFFFF",
         "startAngle": 90, "sweepAngle": -90}
        """)
        #expect(content.contains(##"d="M100 60 L100 0 A100 60 0 0 1 200 60 Z""##), "\(content)")
    }

    @Test("A whole ring is filled even-odd, so its hole stays open")
    func ring() throws {
        let content = try card(child: """
        {"type": "ellipse", "id": "Ell01", "name": "Ring", "width": 200, "height": 120, "fill": "#FFFFFF", "innerRadius": 0.5}
        """)
        #expect(content.contains(##"A50 30 0 1 1 150 60 Z" fill="#FFFFFF" fillRule="evenodd""##), "\(content)")
    }

    // MARK: - Gaps

    @Test("A gap off Tailwind's scale is written as an arbitrary value, not dropped")
    func offScaleGap() throws {
        let content = try card(child: ##"{"type": "rectangle", "id": "Rect1", "name": "Box", "width": 20, "height": 20}"##, gap: ##", "gap": 30"##)
        #expect(content.contains("gap-[30px]"), "\(content)")
    }
}
