//
//  SizedNoteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Notes, prompts and contexts take `width`, `height` and the TextStyle keys Pen's schema
/// gives them (`Note extends Entity, Size, TextStyle`), and a note with no size lays out
/// at the post-it's 200×200. See `project/2026-10-04-post-it-design.md`, Model.
@MainActor
struct SizedNoteTests {
    // MARK: - Fixtures

    /// A 1000×1000 absolute board holding an unsized note, a Pen-style 0×0 note, a sized
    /// note, an unsized prompt and an unsized context.
    private static let board = """
    {
      "version": "2.17",
      "children": [
        {
          "id": "Brd01", "name": "Board", "type": "frame", "x": 0, "y": 0,
          "width": 1000, "height": 1000, "layout": "none",
          "children": [
            { "id": "Nte01", "name": "Unsized", "type": "note", "content": "hi", "x": 0, "y": 0 },
            { "id": "Nte02", "name": "Zero", "type": "note", "content": "hi", "x": 300, "y": 0,
              "width": 0, "height": 0 },
            { "id": "Nte03", "name": "Sized", "type": "note", "content": "hi", "x": 600, "y": 0,
              "width": 120, "height": 80 },
            { "id": "Prm01", "name": "Prompt", "type": "prompt", "content": "hi", "x": 0, "y": 300 },
            { "id": "Ctx01", "name": "Context", "type": "context", "content": "hi", "x": 0, "y": 600 }
          ]
        }
      ]
    }
    """

    /// The TextStyle keys and a valid value for each, as `set` writes them.
    private static let textStyle: [String: AnyCodable] = [
        "kind.fontFamily": .string("Inter"),
        "kind.fontSize": .int(20),
        "kind.fontWeight": .string("700"),
        "kind.fontStyle": .string("italic"),
        "kind.letterSpacing": .int(1),
        "kind.lineHeight": .double(1.3),
        "kind.textAlign": .string("center"),
        "kind.textAlignVertical": .string("middle"),
        "kind.underline": .bool(true),
        "kind.strikethrough": .bool(true),
        "kind.href": .string("https://example.com"),
    ]

    private func makeDocument(_ json: String = board) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(json))
    }

    /// A JSON number as a `Double`, whichever case the codec read it into.
    private func number(_ value: AnyCodable) -> Double? {
        switch value {
        case let .int(int): Double(int)
        case let .double(double): double
        default: nil
        }
    }

    /// Every note in a tree, depth first.
    private func notes(in nodes: [PenNode]) -> [PenNode] {
        nodes.flatMap { node -> [PenNode] in
            var found: [PenNode] = []
            if case .note = node.kind { found.append(node) }
            if case let .frame(frame) = node.kind { found += notes(in: frame.children ?? []) }
            return found
        }
    }

    private func rects(_ json: String = board) throws -> [String: PenRect] {
        try PenLayoutEngine.layout(PenParser.parse(json))
    }

    // MARK: - set and add

    @Test("set accepts width, height and every TextStyle key on a note")
    func setAcceptsSizeAndTextStyle() throws {
        let document = try makeDocument()
        let note = try #require(NodeAddress("Board/Unsized"))
        var props = Self.textStyle
        props["kind.width"] = .int(240)
        props["kind.height"] = .int(160)

        _ = try BatchApplier.applyOne(.set(BatchOperation.SetOp(target: note, props: props)), to: document)

        let written = try #require(document.node(id: "Nte01"))
        for (path, value) in props {
            let read = try NodePropertyCodec.value(at: path, of: written)
            #expect(read == value || number(read) == number(value), "\(path) read back \(read)")
        }
    }

    @Test("set accepts width, height and the TextStyle keys on a prompt and a context")
    func setAcceptsSizeOnPromptAndContext() throws {
        let document = try makeDocument()
        for (address, id) in [("Board/Prompt", "Prm01"), ("Board/Context", "Ctx01")] {
            let target = try #require(NodeAddress(address))
            _ = try BatchApplier.applyOne(
                .set(BatchOperation.SetOp(target: target, props: ["kind.width": .int(50), "kind.fontSize": .int(18)])),
                to: document
            )
            let node = try #require(document.node(id: id))
            #expect(try number(NodePropertyCodec.value(at: "kind.width", of: node)) == 50)
            #expect(try number(NodePropertyCodec.value(at: "kind.fontSize", of: node)) == 18)
        }
    }

    @Test("add accepts a note carrying width, height and TextStyle keys")
    func addAcceptsASizedNote() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Added", "content": "new",
            "width": 220, "height": 180, "fontSize": 15, "fontFamily": "Inter", "textAlign": "center",
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))),
            to: document
        )

        let addedID = try #require(result.created.first?.id)
        let added = try #require(document.node(id: addedID))
        #expect(try number(NodePropertyCodec.value(at: "kind.width", of: added)) == 220)
        #expect(try number(NodePropertyCodec.value(at: "kind.fontSize", of: added)) == 15)
        #expect(try NodePropertyCodec.value(at: "kind.textAlign", of: added) == .string("center"))
    }

    @Test("A note's width and fontSize are claimed by the model, not kept as extras")
    func sizeIsNotAnExtra() throws {
        let document = try PenParser.parse(Self.board)
        let board = try #require(document.children.first)
        guard case let .frame(frame) = board.kind else {
            Issue.record("the board is not a frame")
            return
        }
        let zero = try #require(frame.children?.first { $0.id == "Nte02" })
        #expect(zero.extras.isEmpty, "width/height landed in extras: \(zero.extras)")
    }

    // MARK: - Layout

    /// Changed 2026-10-11 (leaf dbLtoJ): prompts and contexts are drawn as cards in the
    /// rev 2 look, so an unsized one lays out at the card size rather than 0×0, which
    /// would draw nothing.
    @Test("An unsized note lays out at 200×200, and an unsized prompt and context at the card size")
    func unsizedNoteIs200() throws {
        let all = try rects()
        let rect = try #require(all["Nte01"])
        #expect(rect.width == 200)
        #expect(rect.height == 200)
        for id in ["Prm01", "Ctx01"] {
            let other = try #require(all[id])
            #expect(other.width == PenPostIt.cardDefaultWidth, "\(id) laid out at \(other)")
            #expect(other.height == PenPostIt.cardDefaultHeight, "\(id) laid out at \(other)")
        }
    }

    @Test("A note Pen saved as 0×0 lays out at 200×200")
    func zeroNoteIs200() throws {
        let rect = try #require(rects()["Nte02"])
        #expect(rect.width == 200)
        #expect(rect.height == 200)
    }

    @Test("A sized note lays out at its own size")
    func sizedNoteKeepsItsSize() throws {
        let rect = try #require(rects()["Nte03"])
        #expect(rect.width == 120)
        #expect(rect.height == 80)
    }

    // MARK: - Round trip

    @Test("A Pen-saved note with width 0, height 0 and a fontSize reads them typed and round-trips byte for byte")
    func roundTripsByteForByte() throws {
        let file = """
        {
          "children": [
            {
              "content": "Hello",
              "fontSize": 16,
              "height": 0,
              "id": "Nte01",
              "lineHeight": 1.3,
              "metadata": {
                "author": "claude",
                "kind": "question",
                "state": "open",
                "type": "postit"
              },
              "name": "Note",
              "type": "note",
              "width": 0,
              "x": 10,
              "y": 20
            }
          ],
          "version": "2.21"
        }
        """
        let document = try PenParser.parse(file)
        let note = try #require(document.children.first)
        #expect(try number(NodePropertyCodec.value(at: "kind.width", of: note)) == 0)
        #expect(try number(NodePropertyCodec.value(at: "kind.fontSize", of: note)) == 16)
        let written = try PenParser.encodeForFile(document)
        // The file ends with a newline, which the literal leaves off.
        #expect(String(decoding: written, as: UTF8.self) == file + "\n")
    }

    // MARK: - Overrides and variables

    /// A component holding a note, and an instance that overrides the note's fontSize.
    private static let component = """
    {
      "version": "2.17",
      "children": [
        {
          "id": "Cmp01", "name": "Card", "type": "frame", "reusable": true, "x": 0, "y": 0,
          "width": 300, "height": 300, "layout": "none",
          "children": [
            { "id": "Nte01", "name": "Sticky", "type": "note", "content": "hi", "fontSize": 13 }
          ]
        },
        { "id": "Ins01", "name": "Instance", "type": "ref", "ref": "Cmp01", "x": 400, "y": 0,
          "descendants": { "Nte01": { "fontSize": 24 } } }
      ]
    }
    """

    @Test("An instance override of a note's fontSize applies")
    func overrideOfFontSizeApplies() throws {
        let expanded = try PenRefExpander.expand(PenParser.parse(Self.component), for: .canvas)
        let note = try #require(notes(in: expanded.children).first { $0.id != "Nte01" })
        #expect(try number(NodePropertyCodec.value(at: "kind.fontSize", of: note)) == 24)
        let definition = try #require(notes(in: expanded.children).first { $0.id == "Nte01" })
        #expect(try number(NodePropertyCodec.value(at: "kind.fontSize", of: definition)) == 13)
    }

    @Test("override writes a note's fontSize on an instance, and the instance reads it")
    func overrideVerbWritesFontSize() throws {
        let document = try makeDocument(Self.component)
        let target = try #require(NodeAddress("Instance/Sticky"))

        _ = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: target, props: ["fontSize": .int(30)])),
            to: document
        )

        let (expanded, _) = document.expandedDocument()
        let note = try #require(notes(in: expanded.children).first { $0.id != "Nte01" })
        #expect(try number(NodePropertyCodec.value(at: "kind.fontSize", of: note)) == 30)
    }

    @Test("A note's fontSize bound to a variable resolves")
    func variableFontSizeResolves() throws {
        let json = """
        {
          "version": "2.17",
          "variables": { "note-size": { "type": "number", "value": 17 } },
          "children": [
            { "id": "Nte01", "name": "Sticky", "type": "note", "content": "hi", "fontSize": "$note-size",
              "width": "$note-size" }
          ]
        }
        """
        let resolved = try PenVariableResolver.resolve(PenParser.parse(json))
        let note = try #require(resolved.children.first)
        #expect(try number(NodePropertyCodec.value(at: "kind.fontSize", of: note)) == 17)
        #expect(try number(NodePropertyCodec.value(at: "kind.width", of: note)) == 17)
    }

    // MARK: - Diff and invalidation

    @Test("PropertyDiff names a note's changed size and TextStyle keys")
    func diffNamesNoteKeys() throws {
        let before = try #require(makeDocument().node(id: "Nte01"))
        var after = before
        after = try NodePropertyCodec.setting(.int(20), at: "kind.fontSize", on: after)
        after = try NodePropertyCodec.setting(.int(240), at: "kind.width", on: after)

        let changed = PropertyDiff.diffKind(old: before.kind, new: after.kind)
        #expect(changed == ["kind.fontSize", "kind.width"])
    }

    /// Changed 2026-10-11 (leaf uAzSie): a note now grows to fit its text, so its text
    /// and TextStyle move its height and need layout too.
    @Test("A note's size, text and TextStyle changes all need layout")
    func changeCategoryForNotes() throws {
        let before = try #require(makeDocument().node(id: "Nte01"))
        let resized = try NodePropertyCodec.setting(.int(240), at: "kind.width", on: before)
        let restyled = try NodePropertyCodec.setting(.int(20), at: "kind.fontSize", on: before)
        let rewritten = try NodePropertyCodec.setting(.string("new"), at: "kind.content", on: before)

        #expect(ChangeCategory.categorize(oldKind: before.kind, newKind: resized.kind) == .layout)
        #expect(ChangeCategory.categorize(oldKind: before.kind, newKind: restyled.kind) == .layout)
        #expect(ChangeCategory.categorize(oldKind: before.kind, newKind: rewritten.kind) == .layout)
    }

    // MARK: - Lint

    @Test("note-unsized is a notice on an unsized or 0×0 note, and quiet on a sized one")
    func noteUnsizedLint() throws {
        let findings = try DocumentLinter.findings(in: makeDocument())
            .filter { $0.check.rawValue == "note-unsized" }
        #expect(Set(findings.compactMap(\.nodeID)) == ["Nte01", "Nte02"])
        #expect(findings.allSatisfy { $0.severity == .notice })
        let unsized = try #require(findings.first { $0.nodeID == "Nte01" })
        #expect(unsized.message.contains("kind.width=200"))
    }
}
