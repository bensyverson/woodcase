//
//  FigmaImportTextTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// T1's text: content, font, size, line height and growth from `textData`, never from the
/// glyph outlines.
struct FigmaImportTextTests {
    private typealias Fixtures = FigmaImportFixtures

    private static func text(_ name: String, caseID: String = "T1") throws -> PenNode.TextData {
        let node = try Fixtures.node(name, in: Fixtures.imported(caseID).clip.document)
        guard case let .text(data) = node.kind else {
            Issue.record("\(name) is \(node.kind)")
            throw FigmaImportFixtures.FixtureMissing(name: name)
        }
        return data
    }

    @Test("Content, family, weight, style and size come from the node")
    func basics() throws {
        let data = try Self.text("T1a simple")
        #expect(data.content == .literal("Fixture text"))
        #expect(data.fontFamily == .literal("Inter"))
        #expect(data.fontWeight == .literal("400"))
        #expect(data.fontStyle == .literal("normal"))
        #expect(data.fontSize == .literal(32))
        #expect(data.fills?.all == [.color(PenFill.PenColorFill(color: .literal("#1B1B1FFF")))])
    }

    @Test("Figma's auto line height is Pen's natural one; pixels and multiples become multiples of the size")
    func lineHeight() throws {
        #expect(try Self.text("T1a simple").lineHeight == nil)
        #expect(try Self.text("T1b two lines").lineHeight.flatMap(\.literalValue).map { abs($0 - 32.0 / 24) < 1e-9 } == true)
        #expect(try Self.text("T1c fixed").lineHeight.flatMap(\.literalValue).map { abs($0 - 1.2) < 1e-6 } == true)
    }

    @Test("Auto width, auto height and fixed boxes map to Pen's text growth", arguments: [
        ("T1a simple", PenTextGrowth.auto, false, false),
        ("T1b two lines", .fixedWidth, true, false),
        ("T1c fixed", .fixedWidthHeight, true, true),
    ])
    func growth(name: String, growth: PenTextGrowth, hasWidth: Bool, hasHeight: Bool) throws {
        let data = try Self.text(name)
        #expect(data.textGrowth == growth)
        #expect((data.width != nil) == hasWidth && (data.height != nil) == hasHeight)
    }

    @Test("A multi-line string keeps its line break")
    func lines() throws {
        #expect(try Self.text("T1b two lines").content == .literal("Line one\nLine two"))
    }

    @Test("Truncation and list markers are reported", arguments: [
        ("T1c fixed", FigmaImportLoss.Feature.textTruncation),
        ("T1e list bulleted", .textList),
        ("T1e list numbered", .textList),
    ])
    func reported(name: String, feature: FigmaImportLoss.Feature) throws {
        #expect(try Fixtures.losses(name, in: Fixtures.imported("T1")).map(\.feature) == [feature])
    }

    @Test("Mixed styles become spans over the base style")
    func mixed() throws {
        let node = try Fixtures.node("T1d mixed", in: Fixtures.imported("T1").clip.document)
        guard case let .text(data) = node.kind else { return }
        #expect(data.fontWeight == .literal("400") && data.fontSize == .literal(24))
        let spans = try #require(node.common.metadata?.textSpans)
        #expect(spans.text == "Mixed style")
        #expect(spans.runs == [PenTextRun(
            start: 6, end: 11, fontSize: 32, fontWeight: 700, isItalic: true,
            fill: PenHexColor("#D9480FFF")
        )])
        #expect(try Fixtures.losses("T1d mixed", in: Fixtures.imported("T1")).isEmpty)
    }

    @Test("Underline and strikethrough map")
    func decorations() throws {
        #expect(try Self.text("T1g underline").underline == .literal(true))
        #expect(try Self.text("T1g strikethrough").strikethrough == .literal(true))
    }

    @Test("Scripts keep their characters and fonts: CJK, emoji and Arabic", arguments: [
        ("T1f script cjk", "中文", "PingFang SC"),
        ("T1f script emoji", "😀", "Noto Color Emoji"),
        ("T1f script arabic", "مرحبا", "Geeza Pro"),
    ])
    func scripts(name: String, content: String, family: String) throws {
        let data = try Self.text(name)
        #expect(data.content == .literal(content))
        #expect(data.fontFamily == .literal(family))
        #expect(data.lineHeight == nil)
    }

    @Test("Text with an emoji keeps it and its line height, though the emoji's glyph blob is empty")
    func emojiInText() throws {
        let text = Fixtures.nodeChange("TEXT", name: "greeting", id: 40, width: 60, height: 20, extra: [
            "fontSize": .float(16),
            "fontName": .structure(KiwiRecord(typeName: "FontName", fields: [
                "family": .string("Inter"), "style": .string("Medium"), "postscript": .string(""),
            ])),
            "lineHeight": .structure(KiwiRecord(typeName: "Number", fields: ["value": .float(20), "units": .enumeration("PIXELS")])),
            "textData": .message(KiwiRecord(typeName: "TextData", fields: ["characters": .string("Hi 😀")])),
            "textAutoResize": .enumeration("WIDTH_AND_HEIGHT"),
            "fillPaints": .array([Fixtures.solid(0, 0, 0)]),
        ])
        let result = try FigmaImporter().clip(from: Fixtures.message([text]))
        let node = try #require(result.clip.document.children.first)
        guard case let .text(data) = node.kind else {
            Issue.record("\(node.kind)")
            return
        }
        #expect(data.content == .literal("Hi 😀"))
        #expect(data.lineHeight == .literal(1.25))
        #expect(data.fontWeight == .literal("500"))
        #expect(result.losses.isEmpty)
    }

    @Test("A text style or bound variable is resolved to its value and reported", arguments: [
        ("C1", "C1f style-text", FigmaImportLoss.Feature.styleReference),
        ("R1", "R1 text bound", .variableBinding),
    ])
    func boundText(caseID: String, name: String, feature: FigmaImportLoss.Feature) throws {
        let losses = try Fixtures.losses(name, in: Fixtures.imported(caseID))
        #expect(losses.map(\.feature) == [feature])
        #expect(losses.first?.treatment == .resolved)
    }
}
