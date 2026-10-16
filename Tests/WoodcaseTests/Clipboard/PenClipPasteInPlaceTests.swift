//
//  PenClipPasteInPlaceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The two Paste in Place targets: ``PasteTarget/atBoardOffset(in:)`` — the same offset
/// from another board's top-left corner, exactly — and
/// ``PasteTarget/whereCopied(documentID:)``, back where each copy came from.
///
/// In the source, `Page` sits at (100, 200); `Free` is at (5, 6) in it, and `Fill` at
/// (0, 19) in the stack `Card`, so (10, 39) from `Page`'s corner. `Fill` comes first in
/// document order, so first in a clip that holds both.
struct PenClipPasteInPlaceTests {
    private func clip(_ ids: [String], documentID: String? = "doc-A") throws -> PenClip {
        try PenClip.extract(nodeIDs: ids, from: PenClipFixture.document(), documentID: documentID)
    }

    private func board(_ width: Double, layout: String = "none") throws -> EditableDocument {
        try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Board", "type": "frame", "x": 1000, "y": 1000, "width": \(width), "height": \(width),
            "layout": "\(layout)", "clip": true }
        ] }
        """)
    }

    // MARK: - At the board offset

    @Test("Into another board, each copy takes its offset from its own board's corner")
    func boardOffset() throws {
        let plan = try clip(["Free", "Fill"]).plan(into: board(400), at: .atBoardOffset(in: "Board"))

        let inserts = PasteFixture.contentInserts(plan)
        #expect(inserts.map(\.parentID) == ["Board", "Board"])
        #expect(inserts.map(\.node.common.x) == [.literal(10), .literal(5)])
        #expect(inserts.map(\.node.common.y) == [.literal(39), .literal(6)])
    }

    @Test("An offset outside a smaller board still lands exactly, never moved to fit")
    func boardOffsetOutsideSmallBoard() throws {
        let insert = try #require(PasteFixture.contentInserts(
            clip(["Fill"]).plan(into: board(4), at: .atBoardOffset(in: "Board"))
        ).first)

        #expect(insert.node.common.x == .literal(10))
        #expect(insert.node.common.y == .literal(39))
    }

    @Test("A copy from the top level measures its offset from the canvas origin")
    func boardOffsetOfRoot() throws {
        let insert = try #require(PasteFixture.contentInserts(
            clip(["Page"]).plan(into: board(50), at: .atBoardOffset(in: "Board"))
        ).first)

        #expect(insert.parentID == "Board")
        #expect(insert.node.common.x == .literal(100))
        #expect(insert.node.common.y == .literal(200))
    }

    @Test("A clip without origins takes its canvas position as the offset")
    func boardOffsetWithoutOrigins() throws {
        let copied = try clip(["Free"])
        let bare = PenClip(document: copied.document, contentIDs: copied.contentIDs)

        let insert = try #require(PasteFixture.contentInserts(bare.plan(into: board(50), at: .atBoardOffset(in: "Board"))).first)

        #expect(insert.parentID == "Board")
        #expect(insert.node.common.x == .literal(105))
        #expect(insert.node.common.y == .literal(206))
    }

    @Test("A board that is a stack takes the copies into its flow")
    func boardOffsetIntoStack() throws {
        let insert = try #require(PasteFixture.contentInserts(
            clip(["Free"]).plan(into: board(400, layout: "vertical"), at: .atBoardOffset(in: "Board"))
        ).first)

        #expect(insert.parentID == "Board")
        #expect(insert.node.common.x == nil)
        #expect(insert.node.common.y == nil)
    }

    @Test("At a board offset, a missing or non-container target is refused")
    func boardOffsetRefusals() throws {
        let copied = try clip(["Free"])
        let source = try PenClipFixture.document()

        #expect(throws: PasteError.targetNotFound(id: "Ghost")) {
            try copied.plan(into: source, at: .atBoardOffset(in: "Ghost"))
        }
        #expect(throws: PasteError.notAContainer(id: "Free")) {
            try copied.plan(into: source, at: .atBoardOffset(in: "Free"))
        }
    }

    // MARK: - Where copied

    @Test("Back in its own document, each copy returns to its own parent at its own place")
    func whereCopiedSameDocument() throws {
        let source = try PenClipFixture.document()

        let plan = try clip(["Free", "Fill"]).plan(into: source, at: .whereCopied(documentID: "doc-A"))

        let inserts = PasteFixture.contentInserts(plan)
        #expect(inserts.map(\.parentID) == ["Card", "Page"])
        #expect(inserts[0].node.common.x == nil, "a stack lays its pasted child out")
        #expect(inserts[0].node.common.y == nil)
        #expect(inserts[1].node.common.x == .literal(5))
        #expect(inserts[1].node.common.y == .literal(6))
    }

    @Test("In another document, a copy lands at its canvas position inside the board under its center")
    func whereCopiedOtherDocument() throws {
        let source = try PenClipFixture.document()

        let plan = try clip(["Fill"]).plan(into: source, at: .whereCopied(documentID: "doc-B"))

        let insert = try #require(PasteFixture.contentInserts(plan).first)
        #expect(insert.parentID == "Page")
        #expect(insert.node.common.x == .literal(10))
        #expect(insert.node.common.y == .literal(39))
    }

    @Test("Without a document id on either side, the copy is not taken to be back home")
    func whereCopiedWithoutIDs() throws {
        let source = try PenClipFixture.document()

        let plan = try clip(["Fill"], documentID: nil).plan(into: source, at: .whereCopied(documentID: nil))

        #expect(PasteFixture.contentInserts(plan).first?.parentID == "Page")
    }

    @Test("Each copy whose parent was deleted falls back on its own; the others go home")
    func whereCopiedPerRoot() throws {
        let copied = try clip(["Free", "Fill"])
        let source = try PenClipFixture.document()
        try source.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Card")))

        let inserts = try PasteFixture.contentInserts(copied.plan(into: source, at: .whereCopied(documentID: "doc-A")))

        #expect(inserts.map(\.parentID) == ["Page", "Page"])
        #expect(inserts.map(\.node.common.x) == [.literal(10), .literal(5)])
        #expect(inserts.map(\.node.common.y) == [.literal(39), .literal(6)])
    }

    @Test("With no board under it, a copy whose parent is missing lands at the top level, where it was")
    func whereCopiedTopLevelFallback() throws {
        let insert = try #require(PasteFixture.contentInserts(
            clip(["Fill"]).plan(into: PasteFixture.empty(), at: .whereCopied(documentID: "doc-B"))
        ).first)

        #expect(insert.parentID == nil)
        #expect(insert.node.common.x == .literal(110))
        #expect(insert.node.common.y == .literal(239))
    }

    @Test("Where boards overlap under the copy's center, the top-most takes it")
    func whereCopiedTopMostBoard() throws {
        let target = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Under", "type": "frame", "x": 0, "y": 0, "width": 400, "height": 400, "layout": "none" },
          { "id": "Over", "type": "frame", "x": 100, "y": 200, "width": 50, "height": 50, "layout": "none" },
          { "id": "Shape", "type": "rectangle", "x": 0, "y": 0, "width": 400, "height": 400 }
        ] }
        """)

        let insert = try #require(PasteFixture.contentInserts(
            clip(["Free"]).plan(into: target, at: .whereCopied(documentID: "doc-B"))
        ).first)

        #expect(insert.parentID == "Over", "a shape on top is not a board")
        #expect(insert.node.common.x == .literal(5))
        #expect(insert.node.common.y == .literal(6))
    }

    @Test("A copy from the top level goes back to the top level, where it was, even over a board")
    func whereCopiedRoot() throws {
        let target = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Board", "type": "frame", "x": 0, "y": 0, "width": 5000, "height": 5000, "layout": "none" }
        ] }
        """)

        let inserts = try PasteFixture.contentInserts(
            clip(["Free", "Lib"]).plan(into: target, at: .whereCopied(documentID: "doc-B"))
        )

        #expect(inserts.map(\.parentID) == [nil, "Board"], "the canvas is in every document; Free's parent is not")
        #expect(inserts.map(\.node.common.x) == [.literal(0), .literal(105)])
        #expect(inserts.map(\.node.common.y) == [.literal(0), .literal(206)])
    }

    @Test("A copy drawn inside an instance cannot go back into it, so it falls back to the board")
    func whereCopiedOutOfInstance() throws {
        let source = try PenClipFixture.document()
        let copied = try PenClip.extract(nodeIDs: ["BtnI/IcoRef/Icon"], from: source, documentID: "doc-A")

        let plan = try copied.plan(into: source, at: .whereCopied(documentID: "doc-A"))

        let insert = try #require(PasteFixture.contentInserts(plan).last)
        #expect(insert.parentID == "Page")
    }

    @Test("Going back into a component refuses a copy that would draw that component inside itself")
    func whereCopiedLoop() throws {
        let target = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Comp", "name": "Comp", "type": "frame", "reusable": true, "x": 0, "y": 0, "width": 100,
            "height": 100, "layout": "none",
            "children": [ { "id": "Slot", "type": "frame", "x": 0, "y": 0, "width": 50, "height": 50, "layout": "none" } ] }
        ] }
        """)
        let clip = try PenClip(
            document: PenParser.parse(Data("""
            { "version": "2.17", "children": [ { "id": "Inst", "type": "ref", "ref": "Comp", "x": 0, "y": 0 } ] }
            """.utf8)),
            contentIDs: ["Inst"],
            origins: ["Inst": PenClip.Origin(
                parentID: "Slot", offset: PenPoint(x: 0, y: 0), boardID: "Comp", boardOffset: PenPoint(x: 0, y: 0)
            )],
            sourceDocumentID: "doc-A"
        )

        #expect(throws: PasteError.self) {
            try clip.plan(into: target, at: .whereCopied(documentID: "doc-A"))
        }
    }
}
