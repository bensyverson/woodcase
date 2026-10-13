//
//  PenClipSelectionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What ``PenClip/extract(nodeIDs:from:)`` copies for the ids it is given: a node inside
/// an instance comes out as drawn and detached, the roots come out in document order,
/// a node under another copied node is not copied twice, and the same copy is the same
/// clip every time.
struct PenClipSelectionTests {
    // MARK: - Inside an instance

    @Test("A node inside an instance comes out as drawn, detached, under an id of its own")
    func instanceChildIsDetached() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI/Lbl"], from: document)

        #expect(clip.document.children.count == 1)
        let root = try #require(clip.document.children.first)
        #expect(clip.contentIDs == [root.id])
        #expect(root.id != "Lbl")
        #expect(PenID.isValid(root.id))
        guard case let .text(label) = root.kind else {
            Issue.record("the label did not come out as text")
            return
        }
        #expect(label.content == .literal("Buy"))
    }

    @Test("A nested instance inside an instance comes out detached, with no component")
    func nestedInstanceIsDetached() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI/IcoRef/Icon"], from: document)

        #expect(clip.document.children.count == 1)
        let root = try #require(clip.document.children.first)
        guard case .frame = root.kind else {
            Issue.record("the nested instance did not come out as its component's frame")
            return
        }
        #expect(root.common.reusable != true)
        #expect(clip.document.variables?.keys.sorted() == ["accent", "brand"])
    }

    @Test("An instance's own expanded id copies the instance, not its drawing")
    func instanceRootByExpandedID() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI/Btn"], from: document)

        #expect(clip.contentIDs == ["BtnI"])
    }

    // MARK: - Order and overlap

    @Test("Roots come out in document order, whatever order they were asked for in")
    func documentOrder() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Free", "Card"], from: document)

        #expect(Array(clip.contentIDs.prefix(2)) == ["Card", "Free"])
        #expect(Array(clip.document.children.map(\.id).prefix(2)) == ["Card", "Free"])
    }

    @Test("A node under another copied node is copied once, inside it")
    func nestedSelectionIsDropped() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Card", "BtnI", "BtnI/Lbl", "Fill"], from: document)

        #expect(clip.contentIDs == ["Card"])
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("An id that names no node is refused")
    func unknownIDIsRefused() throws {
        let document = try PenClipFixture.document()

        #expect(throws: EditingError.nodeNotFound(id: "Nope1")) {
            try PenClip.extract(nodeIDs: ["Free", "Nope1"], from: document)
        }
    }

    // MARK: - Determinism

    @Test("Copying twice, from two copies of a document, gives equal clips and equal bytes")
    func deterministic() throws {
        let ids = ["BtnI/Lbl", "Free", "AliasI", "BtnI/IcoRef/Icon"]

        let first = try PenClip.extract(nodeIDs: ids, from: PenClipFixture.document())
        let second = try PenClip.extract(nodeIDs: ids, from: PenClipFixture.document())

        #expect(first.contentIDs.count == 4)
        #expect(first == second)
        #expect(try PenParser.encodeForFile(first.document) == PenParser.encodeForFile(second.document))
        PenClipFixture.expectSelfContained(first)
    }
}
