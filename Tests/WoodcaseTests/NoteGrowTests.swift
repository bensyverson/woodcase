//
//  NoteGrowTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A note grows to fit its text and never shrinks below its set height; its width stays
/// as set. Penumbra's notes design, decision 4.
struct NoteGrowTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let long = String(repeating: "A long note keeps on going well past its box. ", count: 8)

    /// A board holding one note with the given content, size and metadata.
    private func board(content: String, width: Int? = 120, height: Int? = 80, metadata: String = "") -> String {
        let size = [width.map { #""width": \#($0)"# }, height.map { #""height": \#($0)"# }]
            .compactMap(\.self).joined(separator: ", ")
        let encoded = String(data: try! JSONEncoder().encode(content), encoding: .utf8)!
        return """
        {"version": "2.17", "children": [
          {"id": "Brd01", "type": "frame", "x": 0, "y": 0, "width": 1000, "height": 1000, "layout": "none",
           "children": [
             {"id": "Nte01", "type": "note", "x": 10, "y": 10, "content": \(encoded)\(size.isEmpty ? "" : ", " + size)\(metadata)}
           ]}
        ]}
        """
    }

    private func noteRect(_ json: String) throws -> PenRect {
        try #require(PenLayoutEngine.layout(PenParser.parse(json))["Nte01"])
    }

    private func noteNode(_ json: String) throws -> PenNode {
        let document = try PenParser.parse(json)
        guard case let .frame(frame) = document.children.first?.kind else { throw CocoaError(.coderInvalidValue) }
        return try #require(frame.children?.first)
    }

    /// One test, so that the guard against growing a short note fails with the growth
    /// it guards until growth exists.
    @Test("A long note grows past its set height to fit its text plus its padding; a short or empty one keeps it")
    func longNoteGrowsShortKeeps() throws {
        for content in ["hi", ""] {
            let short = try noteRect(board(content: content))
            #expect(short.width == 120)
            #expect(short.height == 80)
        }
        let json = board(content: Self.long)
        let rect = try noteRect(json)
        let node = try noteNode(json)
        let layout = try #require(PenTextLayout(note: node, size: CGSize(width: 120, height: 80)))
        #expect(rect.width == 120)
        #expect(rect.height > 80)
        #expect(rect.height == Double(layout.blockHeight) + PenPostIt.textInsets.vertical)
    }

    @Test("An unsized note with long text grows from the default size")
    func unsizedNoteGrows() throws {
        let rect = try noteRect(board(content: Self.long + Self.long, width: nil, height: nil))
        #expect(rect.width == PenPostIt.defaultSize)
        #expect(rect.height > PenPostIt.defaultSize)
    }

    @Test("A note grows by its markdown's display text and runs, in its metadata style")
    func growsByMarkdownStyle() throws {
        let plain = try noteRect(board(content: "# Heading one\n# Heading two\n# Heading three"))
        let larger = try noteRect(board(
            content: "# Heading one\n# Heading two\n# Heading three",
            metadata: #", "metadata": {"type": "woodcase", "woodcase": {"fontSize": 24}}"#
        ))
        #expect(plain.height > 80)
        #expect(larger.height > plain.height)
    }

    @Test("Incremental layout grows a note the same as a full layout")
    func incrementalAgrees() throws {
        let document = try PenParser.parse(board(content: Self.long))
        let full = PenLayoutEngine.layout(document)
        let incremental = PenLayoutEngine.layoutIncremental(document, previousRects: [:], dirtyNodeIDs: ["Nte01"])
        #expect(incremental["Nte01"] == full["Nte01"])
        #expect((full["Nte01"]?.height ?? 0) > 80)
    }

    // MARK: - Chrome

    @Test("A note's author line adds to its bottom inset, so a long note grows by it too")
    func authorLineGrows() throws {
        let style = PenPostIt.Style.standard
        let json = board(content: Self.long, metadata: #", "metadata": {"type": "woodcase", "woodcase": {"author": "ben"}}"#)
        let node = try noteNode(json)
        let insets = try #require(PenPostIt.bodyInsets(of: node))
        let footer = style.labelFontSize * style.labelLineHeight
        #expect(abs(insets.bottom - (PenPostIt.textInsets.bottom + style.footerGap + footer)) < 0.001)
        #expect(insets.top == PenPostIt.textInsets.top)

        let rect = try noteRect(json)
        let plain = try noteRect(board(content: Self.long))
        let layout = try #require(PenTextLayout(note: node, size: CGSize(width: 120, height: 80)))
        #expect(abs(rect.height - (Double(layout.blockHeight) + insets.vertical)) < 0.001)
        #expect(abs(rect.height - plain.height - (insets.bottom - PenPostIt.textInsets.bottom)) < 0.001)
    }

    @Test("An unsized prompt and context lay out at the card size")
    func unsizedCards() throws {
        let json = """
        {"version": "2.17", "children": [
          {"id": "Prm01", "type": "prompt", "x": 0, "y": 0, "content": "Go"},
          {"id": "Ctx01", "type": "context", "x": 0, "y": 300, "content": "Stay", "width": 0, "height": 0}
        ]}
        """
        let rects = try PenLayoutEngine.layout(PenParser.parse(json))
        for id in ["Prm01", "Ctx01"] {
            let rect = try #require(rects[id])
            #expect(rect.width == PenPostIt.cardDefaultWidth && rect.height == PenPostIt.cardDefaultHeight, "\(id): \(rect)")
        }
    }

    @Test("A long prompt grows to fit its text between its header and its run row")
    func promptGrows() throws {
        let encoded = try String(data: JSONEncoder().encode(Self.long + Self.long), encoding: .utf8)!
        let json = """
        {"version": "2.17", "children": [{"id": "Prm01", "type": "prompt", "x": 0, "y": 0, "content": \(encoded), "model": "m"}]}
        """
        let document = try PenParser.parse(json)
        let node = try #require(document.children.first)
        let rect = try #require(PenLayoutEngine.layout(document)["Prm01"])
        let insets = try #require(PenPostIt.bodyInsets(of: node))
        let layout = try #require(PenTextLayout(note: node, size: CGSize(width: rect.width, height: rect.height)))
        #expect(rect.height > PenPostIt.cardDefaultHeight)
        #expect(abs(rect.height - (Double(layout.blockHeight) + insets.vertical)) < 0.001)
        #expect(layout.blockHeight <= layout.box.height, "the grown prompt still clips its text")
    }

    // MARK: - Invalidation

    @Test("A change to a note's author needs layout, since the footer moves its height; its state does not")
    func footerKeysNeedLayout() throws {
        let before = try noteNode(board(content: "hi"))
        func with(_ key: PenMetadata.WoodcaseKey, _ value: AnyCodable) -> PenNodeCommon {
            var common = before.common
            var metadata = common.metadata ?? PenMetadata(type: nil)
            metadata[woodcase: key] = value
            common.metadata = metadata
            return common
        }
        #expect(ChangeCategory.categorize(oldCommon: before.common, newCommon: with(.author, .string("ben"))) == .layout)
        #expect(ChangeCategory.categorize(oldCommon: before.common, newCommon: with(.state, .string("resolved"))) == .renderOnly)
        #expect(ChangeCategory.categorize(oldCommon: before.common, newCommon: with(.requestedBy, .string("ben"))) == .renderOnly)
    }

    @Test("A prompt's text needs layout, since it grows to fit it")
    func promptTextNeedsLayout() {
        let old = PenNode.Kind.prompt(PenNode.PromptData(content: .literal("a")))
        let new = PenNode.Kind.prompt(PenNode.PromptData(content: .literal("a longer text")))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
        let context = PenNode.Kind.context(PenNode.ContextData(content: .literal("a")))
        let restyled = PenNode.Kind.context(PenNode.ContextData(content: .literal("a"), fontSize: .literal(30)))
        #expect(ChangeCategory.categorize(oldKind: context, newKind: restyled) == .layout)
    }

    @Test("A note's text or text style change needs layout, since its height follows them")
    func noteTextChangeNeedsLayout() throws {
        let before = try noteNode(board(content: "hi"))
        let rewritten = try NodePropertyCodec.setting(.string(Self.long), at: "kind.content", on: before)
        let restyled = try NodePropertyCodec.setting(.int(30), at: "kind.fontSize", on: before)
        #expect(ChangeCategory.categorize(oldKind: before.kind, newKind: rewritten.kind) == .layout)
        #expect(ChangeCategory.categorize(oldKind: before.kind, newKind: restyled.kind) == .layout)
    }

    @Test("A change to a note's metadata text style, or a text's spans, needs layout; a tint only a redraw")
    func metadataChanges() throws {
        let before = try noteNode(board(content: "hi"))
        func with(_ key: PenMetadata.WoodcaseKey, _ value: AnyCodable) -> PenNodeCommon {
            var common = before.common
            var metadata = common.metadata ?? PenMetadata(type: nil)
            metadata[woodcase: key] = value
            common.metadata = metadata
            return common
        }
        #expect(ChangeCategory.categorize(oldCommon: before.common, newCommon: with(.fontSize, .int(30))) == .layout)
        #expect(ChangeCategory.categorize(oldCommon: before.common, newCommon: with(.spans, .dictionary([:]))) == .layout)
        #expect(ChangeCategory.categorize(oldCommon: before.common, newCommon: with(.tint, .string("#A5D6A7"))) == .renderOnly)
    }
}
