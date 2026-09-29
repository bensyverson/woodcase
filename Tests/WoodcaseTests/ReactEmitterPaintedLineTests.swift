//
//  ReactEmitterPaintedLineTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A full-width line whose stroke is a gradient or a stack of fills draws that paint across
/// its band, not `currentColor` (leaf 4fZZ38; `render-painted-lines`).
struct ReactEmitterPaintedLineTests {
    /// The `Card` component's code, holding one full-width line stroked with `stroke`.
    private func emit(stroke: String, width: Double = 6) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical", "width": 200,
           "children": [{"type": "line", "id": "Lin01", "width": "fill_container", "height": 0,
                         "stroke": \(stroke), "strokeWidth": \(width)}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    private static let gradient = ##"{"type": "gradient", "gradientType": "linear", "rotation": 90, "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}"##

    @Test("A gradient stroke paints the band with the gradient")
    func gradientStroke() throws {
        let content = try emit(stroke: Self.gradient)
        #expect(!content.contains("currentColor"), "\(content)")
        #expect(content.contains("linear-gradient("), "\(content)")
        #expect(content.contains("height: 6,"), "\(content)")
        #expect(content.contains("marginTop: -3,"), "\(content)")
    }

    @Test("A stack of fills paints the band with every layer")
    func stackedStroke() throws {
        let content = try emit(stroke: ##"["#FF9500", {"type": "color", "color": "#007AFF80"}]"##, width: 10)
        #expect(!content.contains("currentColor"), "\(content)")
        #expect(content.contains("#007AFF80"), "\(content)")
        #expect(content.contains("#FF9500"), "\(content)")
        #expect(content.contains("height: 10,"), "\(content)")
    }

    /// A flat line's box has no height, which would make its paint server's transform
    /// singular and draw nothing; the paint is laid over the stroke's band instead, as the
    /// full-width band is (`render-painted-lines-fixed`).
    @Test("A fixed flat line lays its gradient over the stroke's band")
    func fixedFlatLineGradient() throws {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "none", "width": 200, "height": 40,
           "children": [{"type": "line", "id": "Lin01", "x": 10, "y": 20, "width": 180, "height": 0,
                         "stroke": \(Self.gradient), "strokeWidth": 10}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        #expect(content.contains("gradientTransform=\"matrix("), "\(content)")
        #expect(!content.contains("matrix(0 0 180 0"), "\(content)")
    }

    /// Green on its first run: the plain color keeps its border.
    @Test("A plain color stroke keeps its top border")
    func plainStroke() throws {
        let content = try emit(stroke: ##""#FF0000""##)
        #expect(content.contains("borderTop: \"6px solid #FF0000\""), "\(content)")
    }
}
