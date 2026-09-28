//
//  PenFlatStrokeModelTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Covers the .pen 2.17 flat stroke keys on every node kind that can carry a stroke.
struct PenFlatStrokeModelTests {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Decoding

    @Test("A rectangle decodes every flat stroke key")
    func rectangleDecodesFlatKeys() throws {
        let json = Data("""
        {"width":100,"height":100,"stroke":"#000000","strokeWidth":2,
         "strokeAlignment":"inner","strokeLinecap":"round","strokeLinejoin":"bevel"}
        """.utf8)
        let data = try decoder.decode(PenNode.RectangleData.self, from: json)
        #expect(data.stroke == .single(.shorthand("#000000")))
        #expect(data.strokeWidth == .uniform(.literal(2)))
        #expect(data.strokeAlignment == .inner)
        #expect(data.strokeLinecap == .round)
        #expect(data.strokeLinejoin == .bevel)
    }

    @Test("A per-side strokeWidth decodes from an object, not an array")
    func perSideStrokeWidthDecodes() throws {
        let json = Data(#"{"strokeWidth":{"top":1,"right":2,"bottom":3,"left":4}}"#.utf8)
        let data = try decoder.decode(PenNode.RectangleData.self, from: json)
        guard case let .perSide(sides) = data.strokeWidth else {
            Issue.record("Expected a per-side strokeWidth")
            return
        }
        #expect(sides.top == .literal(1))
        #expect(sides.right == .literal(2))
        #expect(sides.bottom == .literal(3))
        #expect(sides.left == .literal(4))
    }

    @Test("A strokeWidth variable reference decodes as a variable")
    func variableStrokeWidthDecodes() throws {
        let json = Data(#"{"strokeWidth":"$borderWidth"}"#.utf8)
        let data = try decoder.decode(PenNode.RectangleData.self, from: json)
        #expect(data.strokeWidth == .uniform(.variable("borderWidth")))
    }

    @Test("A stroke paint decodes from the same shapes as a fill")
    func strokePaintAcceptsFillShapes() throws {
        let shorthand = try decoder.decode(
            PenNode.EllipseData.self, from: Data(##"{"stroke":"#FF0000"}"##.utf8)
        )
        #expect(shorthand.stroke == .single(.shorthand("#FF0000")))

        let structured = try decoder.decode(
            PenNode.EllipseData.self,
            from: Data(##"{"stroke":{"type":"color","color":"#00FF00"}}"##.utf8)
        )
        #expect(structured.stroke == .single(.color(PenFill.PenColorFill(color: .literal("#00FF00")))))
    }

    @Test("A line node decodes the flat stroke keys", arguments: [
        ##"{"width":200,"height":2,"stroke":"#333333","strokeWidth":4}"##,
    ])
    func lineDecodesFlatKeys(json: String) throws {
        let data = try decoder.decode(PenNode.LineData.self, from: Data(json.utf8))
        #expect(data.stroke == .single(.shorthand("#333333")))
        #expect(data.strokeWidth == .uniform(.literal(4)))
    }

    @Test("Every strokable node kind decodes the flat keys")
    func everyStrokableKindDecodes() throws {
        let json = Data(##"{"stroke":"#123456","strokeWidth":3,"strokeAlignment":"outer"}"##.utf8)
        let frame = try decoder.decode(PenNode.FrameData.self, from: json)
        let text = try decoder.decode(PenNode.TextData.self, from: json)
        let ellipse = try decoder.decode(PenNode.EllipseData.self, from: json)
        let path = try decoder.decode(PenNode.PathData.self, from: json)
        let polygon = try decoder.decode(PenNode.PolygonData.self, from: json)
        let line = try decoder.decode(PenNode.LineData.self, from: json)

        for stroke in [frame.stroke, text.stroke, ellipse.stroke, path.stroke, polygon.stroke, line.stroke] {
            #expect(stroke == .single(.shorthand("#123456")))
        }
        for width in [
            frame.strokeWidth, text.strokeWidth, ellipse.strokeWidth,
            path.strokeWidth, polygon.strokeWidth, line.strokeWidth,
        ] {
            #expect(width == .uniform(.literal(3)))
        }
        for alignment in [
            frame.strokeAlignment, text.strokeAlignment, ellipse.strokeAlignment,
            path.strokeAlignment, polygon.strokeAlignment, line.strokeAlignment,
        ] {
            #expect(alignment == .outer)
        }
    }

    // MARK: - Encoding

    @Test("A rectangle encodes the flat stroke keys, and nothing nested")
    func rectangleEncodesFlatKeys() throws {
        let data = PenNode.RectangleData(
            stroke: .single(.shorthand("#000000")),
            strokeWidth: .uniform(.literal(2)),
            strokeLinecap: .round,
            strokeLinejoin: .bevel,
            strokeAlignment: .inner
        )
        let json = try String(decoding: encoder.encode(data), as: UTF8.self)
        #expect(json.contains(##""stroke":"#000000""##))
        #expect(json.contains(#""strokeWidth":2"#))
        #expect(json.contains(#""strokeLinecap":"round""#))
        #expect(json.contains(#""strokeLinejoin":"bevel""#))
        #expect(json.contains(#""strokeAlignment":"inner""#))
    }

    @Test("A per-side strokeWidth encodes as an object")
    func perSideStrokeWidthEncodes() throws {
        let data = PenNode.RectangleData(
            strokeWidth: .perSide(PenStrokeWidth.Sides(top: .literal(1), right: nil, bottom: .literal(3), left: nil))
        )
        let json = try String(decoding: encoder.encode(data), as: UTF8.self)
        #expect(json.contains(#""top":1"#))
        #expect(json.contains(#""bottom":3"#))
        #expect(!json.contains("["))
    }

    @Test("Flat stroke keys round-trip through encode and decode")
    func flatKeysRoundTrip() throws {
        let original = PenNode.PathData(
            geometry: "M0 0l10 0z",
            stroke: .single(.shorthand("#ABCDEF")),
            strokeWidth: .perSide(PenStrokeWidth.Sides(top: .literal(1), right: .literal(2), bottom: nil, left: .variable("w"))),
            strokeLinecap: .butt,
            strokeLinejoin: .miter,
            strokeAlignment: .center
        )
        let decoded = try decoder.decode(PenNode.PathData.self, from: encoder.encode(original))
        #expect(decoded == original)
    }

    // MARK: - Enum vocabulary

    @Test("Stroke alignment is inner, center or outer")
    func alignmentVocabulary() {
        #expect(PenStrokeAlign(rawValue: "inner") == .inner)
        #expect(PenStrokeAlign(rawValue: "center") == .center)
        #expect(PenStrokeAlign(rawValue: "outer") == .outer)
        #expect(PenStrokeAlign(rawValue: "inside") == nil)
        #expect(PenStrokeAlign(rawValue: "outside") == nil)
    }

    @Test("Stroke linecap is butt, round or square")
    func linecapVocabulary() {
        #expect(PenStrokeCap(rawValue: "butt") == .butt)
        #expect(PenStrokeCap(rawValue: "round") == .round)
        #expect(PenStrokeCap(rawValue: "square") == .square)
        #expect(PenStrokeCap(rawValue: "none") == nil)
    }
}
