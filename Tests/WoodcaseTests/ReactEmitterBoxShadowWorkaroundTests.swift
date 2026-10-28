//
//  ReactEmitterBoxShadowWorkaroundTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter writes what WebKit draws wrong, and what a theme's fill shows:
/// an opaque pure-black outer `box-shadow` is written `#010101` (leaf `S1cB6z`), and a box
/// filled with a theme color keeps its background blur.
struct ReactEmitterBoxShadowWorkaroundTests {
    // MARK: - Helpers

    /// The emitted `Card` component, whose one child is `child` (a JSON object).
    private func card(_ child: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    /// A filled rectangle casting one outer shadow of `color`.
    private func rectangle(shadowColor color: String) throws -> String {
        try card(##"{"type": "rectangle", "id": "R1", "width": 100, "height": 100, "fill": "#FF0000", "effect": {"type": "shadow", "shadowType": "outer", "color": "\##(color)", "offset": {"x": 10, "y": 14}, "blur": 4}}"##)
    }

    // MARK: - Opaque black box-shadows

    @Test("An opaque pure-black outer box-shadow is written #010101, which WebKit draws", arguments: ["#000000FF", "#000000", "#000"])
    func opaqueBlackBoxShadow(color: String) throws {
        let content = try rectangle(shadowColor: color)
        #expect(content.contains(##"boxShadow: "10px 14px 4px #010101","##), "\(content)")
    }

    @Test("A blended opaque-black shadow's layer is written #010101 too")
    func opaqueBlackShadowLayer() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "width": 100, "height": 100, "fill": "#FF0000", "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 10, "y": 14}, "blur": 4, "blendMode": "multiply"}}"##)
        #expect(content.contains(##"boxShadow: "10px 14px 4px #010101","##), "\(content)")
    }

    /// Green on its first run: a guard on what the workaround must leave alone.
    @Test("A translucent or non-black shadow is written as it is", arguments: ["#00000080", "#111111"])
    func otherShadowColorsKept(color: String) throws {
        let content = try rectangle(shadowColor: color)
        #expect(content.contains(##"boxShadow: "10px 14px 4px \##(color)","##), "\(content)")
    }

    /// Green on its first run: a guard on what the workaround must leave alone.
    @Test("A text's black shadow is written as it is: WebKit draws a text shadow right")
    func textShadowKept() throws {
        let content = try card(##"{"type": "text", "id": "T1", "content": "Hi", "fill": "#FF0000", "effect": {"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 1, "y": 2}, "blur": 3}}"##)
        #expect(content.contains(##"textShadow: "1px 2px 3px #000000","##), "\(content)")
    }

    // MARK: - Background blur under a theme color

    @Test("A box filled with a theme color keeps its background blur", arguments: ["rectangle", "frame"])
    func themedFillBackdrop(kind: String) throws {
        let content = try card(##"{"type": "\##(kind)", "id": "B1", "width": 100, "height": 100, "fill": "$surface", "effect": {"type": "background_blur", "radius": 8}}"##)
        #expect(content.contains(##"backdropFilter: "blur(4px)","##), "\(content)")
    }
}
