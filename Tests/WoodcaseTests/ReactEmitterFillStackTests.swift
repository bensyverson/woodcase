//
//  ReactEmitterFillStackTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A stack of fills on a CSS box is one `background` list, and CSS takes a bare colour only
/// in its last (bottom) layer: a colour over another fill is written as a flat gradient,
/// or the browser drops the whole declaration and the box paints nothing (leaf 4fZZ38,
/// found on `render-painted-lines-fill-stack`).
struct ReactEmitterFillStackTests {
    /// The `background` value React writes for a rectangle filled with `fills`.
    private func background(_ fills: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "rectangle", "id": "Rec01", "width": 40, "height": 20, "fill": \(fills)}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        let line = try #require(content.components(separatedBy: "\n").first { $0.contains("background:") }, "\(content)")
        return line.trimmingCharacters(in: .whitespaces)
    }

    @Test("A colour over a colour is a flat gradient layer")
    func colourOverColour() throws {
        #expect(try background(##"["#FF9500", "#007AFF80"]"##) == ##"background: "linear-gradient(#007AFF80, #007AFF80), #FF9500","##)
    }

    @Test("A colour over a gradient is a flat gradient layer")
    func colourOverGradient() throws {
        let value = try background(##"[{"type": "gradient", "gradientType": "linear", "rotation": 90, "colors": [{"color": "#FFFFFF", "position": 0}, {"color": "#000000", "position": 1}]}, "#FF000080"]"##)
        #expect(value.hasPrefix(##"background: "linear-gradient(#FF000080, #FF000080), linear-gradient("##), "\(value)")
    }

    @Test("A layer's blend mode is written by its CSS name")
    func blendModeByCSSName() throws {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "rectangle", "id": "Rec01", "width": 40, "height": 20,
                         "fill": ["#FF9500", {"type": "color", "color": "#007AFF80", "blendMode": "colorBurn"}]}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        #expect(content.contains(##"backgroundBlendMode: "color-burn, normal""##), "\(content)")
    }
}
