//
//  ReactEmitterSVGStrokeAlignmentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A plain-colour stroke on a shape React writes as SVG — a polygon, a path, an arc or a
/// donut — placed as Pen places it.
///
/// Pen draws a centred or outer stroke past the node's box, and an inner or outer one on
/// one side of the outline only (`render-per-side-shapes.pen`'s inner and outer boards,
/// `render-strokes-and-paths.pen`). An SVG's `stroke` is always centred and an SVG clips to
/// its viewport, so the SVG is drawn with `overflow="visible"` and an aligned stroke is
/// drawn as a painted stroke is: twice the width, clipped to the shape or masked by it.
struct ReactEmitterSVGStrokeAlignmentTests {
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

    @Test("A centred plain stroke lets the SVG draw past its box", arguments: ReactEmitterSVGFillTests.shapes)
    func centredOverflows(shape: String) throws {
        let content = try card(shape: shape, keys: ##""fill": "#DDDDDD", "stroke": "#FF0000", "strokeWidth": 4"##)
        #expect(content.contains(##"overflow="visible""##), "\(content)")
        #expect(content.contains(##"stroke="#FF0000" strokeWidth="4""##), "\(content)")
    }

    @Test("An inner plain stroke is twice the width, clipped to the shape", arguments: ReactEmitterSVGFillTests.shapes)
    func innerIsClipped(shape: String) throws {
        let keys = ##""fill": "#DDDDDD", "stroke": "#FF0000", "strokeWidth": 4, "strokeAlignment": "inner""##
        let content = try card(shape: shape, keys: keys)
        #expect(content.contains("<clipPath id=\"wc-clip-"), "\(content)")
        #expect(content.contains(##"stroke="#FF0000" strokeWidth="8" clipPath="url(#wc-clip-"##), "\(content)")
    }

    @Test("An outer plain stroke is twice the width, masked by the shape", arguments: ReactEmitterSVGFillTests.shapes)
    func outerIsMasked(shape: String) throws {
        let keys = ##""fill": "#DDDDDD", "stroke": "#FF0000", "strokeWidth": 4, "strokeAlignment": "outer""##
        let content = try card(shape: shape, keys: keys)
        #expect(content.contains(##"overflow="visible""##), "\(content)")
        #expect(content.contains("<mask id=\"wc-mask-"), "\(content)")
        #expect(content.contains(##"stroke="#FF0000" strokeWidth="8" mask="url(#wc-mask-"##), "\(content)")
    }
}
