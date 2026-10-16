//
//  PenClipPasteBackOrderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Back where it came from keeps a copy's place among its parent's children
/// (``PasteTarget/whereCopied(documentID:)``): right after its source node while that is
/// still there, as Duplicate puts it, else at the index it had, clamped to the children
/// there now.
///
/// `Card` is a vertical stack holding `BtnI`, then `Fill`; `Page` holds `Card`, `Free`,
/// `AliasI` and `OuterI`.
struct PenClipPasteBackOrderTests {
    private func plan(
        _ ids: [String],
        deleting deleted: [String] = [],
        documentID: String = "doc-A"
    ) throws -> [EditOperation.InsertNode] {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ids, from: source, documentID: "doc-A")
        for id in deleted {
            try source.apply(.deleteNode(EditOperation.DeleteNode(nodeID: id)))
        }
        return try PasteFixture.contentInserts(clip.plan(into: source, at: .whereCopied(documentID: documentID)))
    }

    @Test("Each copy records its node and its index in its parent")
    func recordsIndex() throws {
        let clip = try PenClip.extract(nodeIDs: ["Fill"], from: PenClipFixture.document())

        #expect(clip.origins?["Fill"]?.index == 1)
        #expect(clip.origins?["Fill"]?.nodeID == "Fill")
        let page = try PenClip.extract(nodeIDs: ["Page"], from: PenClipFixture.document())
        #expect(page.origins?["Page"]?.index == 1, "a root records its place among the roots")
    }

    @Test("A copy goes right after its source node in a stack")
    func afterSourceInStack() throws {
        let inserts = try plan(["BtnI"])

        #expect(inserts.map(\.parentID) == ["Card"])
        #expect(inserts.map(\.index) == [1])
    }

    @Test("A copy goes right after its source node in a free container")
    func afterSourceInFreeContainer() throws {
        #expect(try plan(["Free"]).map(\.index) == [2])
    }

    @Test("Copies from one stack each sit after their own source, in order")
    func severalInOneStack() throws {
        let inserts = try plan(["BtnI", "Fill"])

        #expect(inserts.map(\.parentID) == ["Card", "Card"])
        #expect(inserts.map(\.index) == [1, 3], "BtnI' lands at 1, so Fill has moved to 2")
    }

    @Test("With its source deleted, a copy takes the index it had")
    func recordedIndex() throws {
        #expect(try plan(["Fill"], deleting: ["Fill"]).map(\.index) == [1])
    }

    @Test("The recorded index is clamped to the children there now")
    func clampedIndex() throws {
        #expect(try plan(["Fill"], deleting: ["BtnI", "Fill"]).map(\.index) == [0])
    }

    @Test("Copies whose sources are gone keep their relative order")
    func orderWithoutSources() throws {
        let inserts = try plan(["BtnI", "Fill"], deleting: ["BtnI", "Fill"])

        #expect(inserts.map(\.index) == [0, 1])
    }

    @Test("A copy from the top level goes right after its source root")
    func afterSourceRoot() throws {
        let inserts = try plan(["Lib"])

        #expect(inserts.map(\.parentID) == [nil])
        #expect(inserts.map(\.index) == [1])
    }

    @Test("Away from home, a copy is appended: an index means nothing in another document")
    func appendedElsewhere() throws {
        #expect(try plan(["Lib"], documentID: "doc-B").map(\.index) == [nil])
    }
}
