//
//  ReactEmitterTextBaselineTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A text's first baseline lands on the whole point Pen puts it on.
///
/// CSS puts the first baseline at `ascent + (line-height − ascent − descent) / 2` and
/// WebKit snaps that to a device pixel; Pen puts it on a whole point
/// (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``). IBM Plex Sans at 13 pt on its
/// 17 pt natural line is 13.375 in CSS — 27 px at 2x, where Pen draws 26 — and every
/// `layout-text-*` text sat a pixel low (leaf BpaSrF, `project/2026-09-28-pen-font-faces.md`,
/// finding 2). The emitter moves the element by the difference with a margin pair, which
/// leaves its margin box, and so its layout, as it was.
struct ReactEmitterTextBaselineTests {
    /// The emitted `Card` component, whose one child is a text node with `properties`.
    private func card(_ properties: String) throws -> String {
        TestFontRegistration.registerTestFonts()
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "text", "id": "Lbl01", "name": "Label", \(properties)}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    /// IBM Plex Sans (ascent 1.025 em, descent 0.275 em) at 13 pt: a 17 pt natural line,
    /// CSS's baseline 13.375, Pen's 13.
    @Test("A natural line whose CSS baseline falls below Pen's moves up")
    func naturalLineMovesUp() throws {
        let content = try card(##""content": "Design", "fontFamily": "IBM Plex Sans", "fontSize": 13"##)
        #expect(content.contains("marginTop: -0.375,"), "\(content)")
        #expect(content.contains("marginBottom: 0.375,"), "\(content)")
    }

    /// Inter (ascent 1984/2048 em, descent 494/2048 em) at 16 pt: a 19 pt natural line,
    /// CSS's baseline 15.3203125, Pen's the rounded ascent, 16.
    @Test("A natural line whose CSS baseline falls above Pen's moves down")
    func naturalLineMovesDown() throws {
        let content = try card(##""content": "Hello", "fontFamily": "Inter", "fontSize": 16"##)
        #expect(content.contains("marginTop: 0.67969,"), "\(content)")
        #expect(content.contains("marginBottom: -0.67969,"), "\(content)")
    }

    /// Inter at 16 pt on a 1.5 line: 24 pt both ways, CSS's baseline 17.8203125, Pen's
    /// rounded to 18.
    @Test("A set line height moves the baseline to Pen's rounded half-leading baseline")
    func setLineHeight() throws {
        let content = try card(##""content": "Hello", "fontFamily": "Inter", "fontSize": 16, "lineHeight": 1.5"##)
        #expect(content.contains("marginTop: 0.17969,"), "\(content)")
        #expect(content.contains("marginBottom: -0.17969,"), "\(content)")
    }
}
