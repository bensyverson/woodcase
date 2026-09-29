//
//  ReactEmitterTextLayoutTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter sets a text node's lines the way Pen sets them: at the default
/// optical size, at Pen's natural pitch when no `lineHeight` is given, with its newlines,
/// on one line when its width is auto, and aligned vertically in its box.
struct ReactEmitterTextLayoutTests {
    // MARK: - Helpers

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

    // MARK: - Optical size (Gmh2sB)

    @Test("Text is drawn at the default optical size, as Pen draws every size")
    func opticalSizingOff() throws {
        let content = try card(##""content": "Ink", "fontFamily": "Inter", "fontSize": 44"##)
        #expect(content.contains(##"fontOpticalSizing: "none","##))
    }

    @Test("Text with no font family still turns optical sizing off")
    func opticalSizingOffWithoutFamily() throws {
        let content = try card(##""content": "Ink""##)
        #expect(content.contains(##"fontOpticalSizing: "none","##))
    }

    // MARK: - Natural line height (3Xbv46)

    @Test("Text with no lineHeight is set at Pen's natural pitch for its font, in px")
    func naturalPitch() throws {
        let content = try card(##""content": "Hello", "fontFamily": "Inter", "fontSize": 16"##)
        #expect(content.contains(##"lineHeight: "19px","##))
        #expect(!content.contains("lineHeight: 1.3"))
    }

    @Test("The natural pitch follows the font size")
    func naturalPitchFollowsSize() throws {
        let font = PenTextMeasurer.resolveFont(family: "Inter", size: 44, weight: "bold", style: "normal")
        let pitch = Int(PenTextMeasurer.naturalLineHeight(of: font))
        let content = try card(##""content": "Ink", "fontFamily": "Inter", "fontSize": 44, "fontWeight": "bold""##)
        #expect(content.contains("lineHeight: \"\(pitch)px\","))
    }

    @Test("A family the emitter cannot resolve is set at the browser's normal line height")
    func unknownFamilyIsNormal() throws {
        let content = try card(##""content": "Hello", "fontFamily": "No Such Family Woodcase", "fontSize": 16"##)
        #expect(content.contains(##"lineHeight: "normal","##))
    }

    @Test("Text with no family is set at the browser's normal line height")
    func noFamilyIsNormal() throws {
        let content = try card(##""content": "Hello", "fontSize": 16"##)
        #expect(content.contains(##"lineHeight: "normal","##))
    }

    /// The emitted `Card` component over a document declaring `variables` (a JSON object
    /// body) and themes, whose one child is a text node with `properties`.
    private func card(variables: String, _ properties: String) throws -> String {
        TestFontRegistration.registerTestFonts()
        let document = try PenParser.parse("""
        {"version": "2.17", "themes": {"mode": ["light", "dark"]}, "variables": {\(variables)},
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "text", "id": "Lbl01", "name": "Label", "content": "Hi", \(properties)}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    @Test("A size that changes with the theme is set at the browser's normal line height")
    func themedSizeIsNormal() throws {
        let content = try card(
            variables: ##""size": {"type": "number", "value": [{"value": 16, "theme": {"mode": "light"}}, {"value": 20, "theme": {"mode": "dark"}}]}"##,
            ##""fontFamily": "Inter", "fontSize": "$size""##
        )
        #expect(content.contains(##"lineHeight: "normal","##))
    }

    @Test("A variable that holds one family and size under every theme is measured")
    func constantVariablesAreMeasured() throws {
        let content = try card(
            variables: ##"""
            "face": {"type": "string", "value": [{"value": "Inter", "theme": {"mode": "light"}}, {"value": "Inter", "theme": {"mode": "dark"}}]},
            "size": {"type": "number", "value": 16}
            """##,
            ##""fontFamily": "$face", "fontSize": "$size""##
        )
        #expect(content.contains(##"lineHeight: "19px","##))
    }

    @Test("An explicit lineHeight is still a multiple of the font size")
    func explicitLineHeightKept() throws {
        let content = try card(##""content": "Hello", "fontFamily": "Inter", "fontSize": 16, "lineHeight": 1.5"##)
        #expect(content.contains("lineHeight: 1.5,"))
    }

    @Test("Empty text reserves one line at the natural pitch")
    func emptyTextReservesNaturalPitch() throws {
        let content = try card(##""content": "", "fontFamily": "Inter", "fontSize": 16"##)
        #expect(content.contains("minHeight: 19,"))
    }

    // MARK: - Newlines and wrapping (RgeMUN)

    @Test("Auto-width text stays on one line and keeps its newlines")
    func autoWidthDoesNotWrap() throws {
        let content = try card(##""content": "One line", "fontFamily": "Inter", "fontSize": 16"##)
        #expect(content.contains(##"whiteSpace: "pre","##))
    }

    @Test("Explicit auto growth stays on one line")
    func explicitAutoDoesNotWrap() throws {
        let content = try card(##""content": "One line", "fontFamily": "Inter", "fontSize": 16, "textGrowth": "auto""##)
        #expect(content.contains(##"whiteSpace: "pre","##))
    }

    @Test("Fixed-width text wraps and keeps its newlines")
    func fixedWidthWrapsKeepingNewlines() throws {
        let content = try card(##""content": "Wraps", "textGrowth": "fixed-width", "width": 200"##)
        #expect(content.contains(##"whiteSpace: "pre-wrap","##))
    }

    @Test("Fixed-size text wraps and keeps its newlines")
    func fixedSizeWrapsKeepingNewlines() throws {
        let content = try card(##""content": "Wraps", "textGrowth": "fixed-width-height", "width": 200, "height": 80"##)
        #expect(content.contains(##"whiteSpace: "pre-wrap","##))
    }

    @Test("A newline reaches the page: the content is a string expression JSX does not collapse")
    func newlinesSurviveJSX() throws {
        let content = try card(##""content": "Line one\nLine two", "textGrowth": "fixed-width", "width": 200"##)
        #expect(content.contains(##"{"Line one\nLine two"}"##))
    }

    @Test("Braces and angle brackets in content are written as a string expression")
    func jsxSyntaxInContentIsEscaped() throws {
        let content = try card(##""content": "a {b} <c>""##)
        #expect(content.contains(##"{"a {b} <c>"}"##))
    }

    /// Green on its first run: it pins today's output for plain content, which the change must keep.
    @Test("Plain content stays bare JSX text")
    func plainContentStaysBare() throws {
        let content = try card(##""content": "Hello World""##)
        #expect(content.contains("  Hello World\n"))
        #expect(!content.contains(##"{"Hello World"}"##))
    }

    // MARK: - Vertical alignment (RgeMUN)

    @Test("Middle vertical alignment centers the lines in the box")
    func middleCenters() throws {
        let content = try card(
            ##""content": "Mid", "textGrowth": "fixed-width-height", "width": 200, "height": 80, "textAlignVertical": "middle""##
        )
        #expect(content.contains(##"display: "flex","##))
        #expect(content.contains(##"flexDirection: "column","##))
        #expect(content.contains(##"justifyContent: "center","##))
    }

    @Test("Bottom vertical alignment sets the lines on the box's bottom")
    func bottomSinks() throws {
        let content = try card(
            ##""content": "Low", "textGrowth": "fixed-width-height", "width": 200, "height": 80, "textAlignVertical": "bottom""##
        )
        #expect(content.contains(##"justifyContent: "flex-end","##))
    }

    @Test("Top vertical alignment is the default flow and writes nothing")
    func topWritesNothing() throws {
        let content = try card(
            ##""content": "Top", "textGrowth": "fixed-width-height", "width": 200, "height": 80, "textAlignVertical": "top""##
        )
        #expect(!content.contains("justifyContent"))
        #expect(!content.contains(##"display: "flex","##))
    }
}
