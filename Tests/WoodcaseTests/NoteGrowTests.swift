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

    // MARK: - Invalidation

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
