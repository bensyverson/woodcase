import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A text node's underline and strikethrough, protected from Pen (leaf kyrTTL).
///
/// Pen strips `underline` and `strikethrough` from a text node when it opens a file, and
/// keeps metadata. So whenever a text carries either natively, Woodcase writes them into
/// `metadata.woodcase.textDecoration` too, with the content they were made for; reading a
/// file whose native keys are gone but whose protection is still there restores
/// them, so Woodcase draws them and writes them back. Both keys cover the whole text, so
/// text edited in Pen keeps them too: the protection is made again for the new words (Ben's
/// ruling of 2026-10-15, leaf 0LwfSn).
///
/// `text-decoration.pen` is Woodcase's own write (`woodcase migrate --force`) of two texts
/// with a native underline and strikethrough; `text-decoration.pen-saved.pen` is headless
/// Pen's save of it (pen CLI 0.3.11, 2026-10-15) — native keys stripped, metadata kept —
/// with `t2`'s content edited in Pen before saving.
struct PenTextDecorationTests {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private func text(_ keys: String, metadata: String? = nil) -> String {
        let metadata = metadata.map { #", "metadata": \#($0)"# } ?? ""
        return ##"{"type": "text", "id": "t", "x": 10, "y": 10, "content": "Struck", "fill": "#000000", "fontSize": 24\##(keys)\##(metadata)}"##
    }

    private func document(_ node: String) throws -> PenDocument {
        try PenParser.parse(#"{"version": "2.20", "children": ["# + node + "]}")
    }

    private func data(_ node: PenNode?) throws -> PenNode.TextData {
        guard case let .text(data)? = node?.kind else {
            Issue.record("not a text: \(String(describing: node))")
            throw CancellationError()
        }
        return data
    }

    private static let protection = #"{"type": "woodcase", "woodcase": {"textDecoration": {"text": "Struck", "underline": true, "strikethrough": true}}}"#

    // MARK: - Protecting

    @Test("A text with a native underline and strikethrough holds them in metadata.woodcase.textDecoration too")
    func nativeKeysAreMirrored() throws {
        let node = try #require(document(text(#", "underline": true, "strikethrough": true"#)).children.first)
        #expect(node.textDecoration == PenTextDecoration(text: "Struck", underline: true, strikethrough: true))
        let written = try PenParser.encodeToString(document(text(#", "underline": true, "strikethrough": true"#)))
        #expect(written.contains("textDecoration"), "\(written)")
    }

    @Test("A text with only an underline protects only the underline")
    func onlyUnderline() throws {
        let node = try #require(document(text(#", "underline": true"#)).children.first)
        #expect(node.textDecoration == PenTextDecoration(text: "Struck", underline: true, strikethrough: false))
    }

    @Test("A text with neither, or both false, holds no protection")
    func nothingToProtect() throws {
        #expect(try document(text("")).children.first?.common.metadata == nil)
        #expect(try document(text(#", "underline": false, "strikethrough": false"#)).children.first?.common.metadata == nil)
    }

    @Test("A text whose content or underline is a variable is not protected")
    func variablesAreNotProtected() throws {
        let content = try document(text(#", "underline": true"#).replacingOccurrences(of: #""Struck""#, with: #""$label""#))
        #expect(content.children.first?.textDecoration == nil)
        let underline = try document(text(#", "underline": "$u""#))
        #expect(underline.children.first?.textDecoration == nil)
    }

    // MARK: - Restoring

    @Test("Native keys Pen stripped are restored from fresh protection, and written back")
    func strippedKeysAreRestored() throws {
        let doc = try document(text("", metadata: Self.protection))
        let restored = try data(doc.children.first)
        #expect(restored.underline == .literal(true))
        #expect(restored.strikethrough == .literal(true))
        let written = try PenParser.encodeToString(doc)
        #expect(written.contains(#""underline":true"#), "\(written)")
        #expect(written.contains(#""strikethrough":true"#), "\(written)")
    }

    @Test("Protection made for other words — the text was edited in Pen — still restores, made again for the new words")
    func staleProtectionIsStretched() throws {
        let doc = try document(text("", metadata: Self.protection.replacingOccurrences(of: #""text": "Struck""#, with: #""text": "Older""#)))
        let node = try #require(doc.children.first)
        #expect(try data(node).underline == .literal(true))
        #expect(try data(node).strikethrough == .literal(true))
        #expect(node.textDecoration == PenTextDecoration(text: "Struck", underline: true, strikethrough: true))
    }

    @Test("A native key the file still writes wins over the protection")
    func nativeKeyWins() throws {
        let doc = try document(text(#", "underline": false"#, metadata: Self.protection))
        let node = try #require(doc.children.first)
        #expect(try data(node).underline == .literal(false))
        #expect(try data(node).strikethrough == .literal(true))
        #expect(node.textDecoration == PenTextDecoration(text: "Struck", underline: false, strikethrough: true))
    }

    @Test("Protection that is not the stored form restores nothing")
    func unreadableProtection() throws {
        let doc = try document(text("", metadata: #"{"type": "woodcase", "woodcase": {"textDecoration": {"underline": true}}}"#))
        #expect(try data(doc.children.first).underline == nil)
    }

    @Test("Reading is idempotent: what Woodcase writes reads back the same")
    func idempotent() throws {
        for source in [text(#", "underline": true, "strikethrough": true"#), text("", metadata: Self.protection)] {
            let once = try document(source)
            let twice = try PenParser.parse(PenParser.encode(once))
            #expect(twice == once)
        }
    }

    // MARK: - Pen's own save

    @Test("Pen's save of a protected file reads underlined and struck through, the text Pen edited too")
    func pensSave() throws {
        let doc = try PenParser.parse(contentsOf: Self.fixtures.appendingPathComponent("text-decoration.pen-saved.pen"))
        let board = try #require(doc.children.first)
        let children = board.kind.inlineChildren
        let kept = try data(children.first { $0.id == "t1" })
        #expect(kept.underline == .literal(true))
        #expect(kept.strikethrough == .literal(true))
        let edited = try #require(children.first { $0.id == "t2" })
        #expect(try data(edited).underline == .literal(true))
        #expect(try data(edited).strikethrough == .literal(true))
        #expect(edited.textDecoration?.text == "Edited in Pen")
    }

    @Test("Woodcase draws the underline and strikethrough of a text Pen stripped them from")
    func drawsRestoredDecoration() throws {
        func pixels(_ node: String) throws -> Data {
            let doc = try document(node)
            let image = try #require(PenRenderer.render(doc, layoutRects: PenLayoutEngine.layout(doc), size: CGSize(width: 200, height: 60)))
            return try #require(image.dataProvider?.data as Data?)
        }
        let native = try pixels(text(#", "underline": true, "strikethrough": true"#))
        #expect(try pixels(text("", metadata: Self.protection)) == native)
        #expect(try pixels(text("")) != native)
    }

    // MARK: - Lint

    @Test("text-style-stripped says a protected underline and strikethrough survive Pen, as a notice")
    @MainActor
    func lintSaysProtected() throws {
        let editable = try EditableDocument(from: document(text(#", "underline": true, "strikethrough": true"#)))
        let found = try DocumentLinter.findings(in: editable).filter { $0.check == .textStyleStripped }
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.severity == .notice }, "\(found)")
        #expect(found.allSatisfy { $0.message.contains("metadata.woodcase.textDecoration") }, "\(found)")
    }

    @Test("text-style-stripped counts an underline protected for older words as protected")
    @MainActor
    func lintStaleProtectionStillProtects() throws {
        let editable = try EditableDocument(from: document(text(#", "underline": true"#)))
        try editable.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "t", properties: ["kind.content": .string("New words")]
        )))
        let found = try DocumentLinter.findings(in: editable).filter { $0.check == .textStyleStripped }
        #expect(found.count == 1)
        #expect(found.first?.severity == .notice, "\(found)")
    }

    @Test("text-style-stripped still warns about an underline it cannot protect")
    @MainActor
    func lintWarnsUnprotected() throws {
        let source = text(#", "underline": true"#).replacingOccurrences(of: #""Struck""#, with: #""$label""#)
        let json = #"{"version": "2.20", "variables": {"label": {"type": "string", "value": "Hi"}}, "children": ["# + source + "]}"
        let editable = try EditableDocument(from: PenParser.parse(json))
        let found = try DocumentLinter.findings(in: editable).filter { $0.check == .textStyleStripped }
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
    }
}
