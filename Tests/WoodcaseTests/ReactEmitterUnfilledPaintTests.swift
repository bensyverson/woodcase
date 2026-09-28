//
//  ReactEmitterUnfilledPaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What the React emitter writes for the colour of a text's or an icon's glyphs when the
/// node has no enabled paint, or paint that is not what it seems.
///
/// Pen draws a text or icon with no enabled fill — no `fill` key, an empty list, only
/// disabled fills — as nothing, and an enabled solid whose colour does not parse as black
/// (`render-text-unfilled.pen`, `PenUnfilledTextPaintTests`). An emitted element with no
/// `color` inherits the page's, which is black, so "nothing" has to be written out.
struct ReactEmitterUnfilledPaintTests {
    // MARK: - Helpers

    /// The emitted `Card` component, whose one child is `node` (a JSON object).
    private func card(_ node: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(node)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    /// A text node carrying `fill`, or no fill key when `fill` is `nil`.
    private func text(fill: String?) throws -> String {
        let key = fill.map { ##", "fill": \##($0)"## } ?? ""
        return try card(##"{"type": "text", "id": "Lbl01", "name": "Label", "content": "Hello"\##(key)}"##)
    }

    /// An icon node carrying `fill`, or no fill key when `fill` is `nil`.
    private func icon(fill: String?) throws -> String {
        let key = fill.map { ##", "fill": \##($0)"## } ?? ""
        return try card(
            ##"{"type": "icon", "id": "Ic001", "name": "Glyph", "icon": "square", "library": "lucide", "width": 24, "height": 24\##(key)}"##
        )
    }

    private static let disabledBlack = ##"[{"type": "color", "color": "#000000", "enabled": false}]"##
    private static let disabledRamp = """
    {"type": "gradient", "gradientType": "linear", "rotation": 270, "enabled": false,
     "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}
    """
    private static let disabledRedUnderBlue = ##"[{"type": "color", "color": "#FF0000", "enabled": false}, "#0000FF"]"##

    // MARK: - Text

    @Test("A text with no enabled paint writes a transparent colour", arguments: [
        nil, "[]", disabledBlack, disabledRamp,
    ])
    func unfilledTextIsTransparent(fill: String?) throws {
        let content = try text(fill: fill)
        #expect(content.contains(##"color: "transparent","##), "\(fill ?? "no fill")")
    }

    @Test("A text whose one enabled solid does not parse is black, as Pen draws it")
    func unparsedTextIsBlack() throws {
        let content = try text(fill: ##""#zzzzzz""##)
        #expect(content.contains(##"color: "#000000","##))
        #expect(!content.contains("zzzzzz"))
    }

    @Test("An unfilled text a hover state colours is transparent at rest, not the hover colour")
    func unfilledTextStateBase() throws {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [
           {"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
            "metadata": {"_role": "button"},
            "children": [{"type": "text", "id": "Lbl01", "name": "Label", "content": "Hello", "fill": \(Self.disabledBlack)}]},
           {"type": "frame", "id": "Card2", "name": "Card:hover", "layout": "vertical",
            "children": [{"type": "text", "id": "Lbl02", "name": "Label", "content": "Hello", "fill": "#FF0000"}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        let css = try #require(files.first { $0.path == "states.css" }).content
        #expect(css.contains("--wc-card-label-color: transparent;"), "\(css)")
    }

    // MARK: - Icon

    @Test("An icon with no enabled paint writes a transparent colour", arguments: [
        nil, "[]", disabledBlack, disabledRamp,
    ])
    func unfilledIconIsTransparent(fill: String?) throws {
        let content = try icon(fill: fill)
        #expect(content.contains(##"color="transparent""##), "\(fill ?? "no fill")")
    }

    @Test("An icon skips a disabled colour for the enabled one above it")
    func iconHonoursEnabled() throws {
        let content = try icon(fill: Self.disabledRedUnderBlue)
        #expect(content.contains(##"color="#0000FF""##))
        #expect(!content.contains("#FF0000"))
    }

    @Test("An icon of two enabled colours takes the top one, as Pen paints it over the other")
    func iconTakesTopColour() throws {
        let content = try icon(fill: ##"["#FF0000", "#0000FF"]"##)
        #expect(content.contains(##"color="#0000FF""##))
    }

    @Test("An icon whose one enabled solid does not parse is black, as Pen draws it")
    func unparsedIconIsBlack() throws {
        let content = try icon(fill: ##""#zzzzzz""##)
        #expect(content.contains(##"color="#000000""##))
    }
}
