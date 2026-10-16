//
//  PenClipOriginTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/origins`` records where each copied root came from — its parent, its offset
/// there, its board and its offset from that board's top-left corner — and
/// ``PenClip/sourceDocumentID`` the document, so a Paste in Place can put it back or at
/// the same place in another board.
///
/// `Page` sits at (100, 200); `Free` is at (5, 6) in it, and `Fill` is at (0, 19) in the
/// stack `Card`, which is at (10, 20) in `Page`.
struct PenClipOriginTests {
    @Test("A node copied out of a board records its parent, the board and both offsets")
    func freeChild() throws {
        let clip = try PenClip.extract(nodeIDs: ["Free"], from: PenClipFixture.document())

        #expect(clip.origins == ["Free": PenClip.Origin(
            parentID: "Page", offset: PenPoint(x: 5, y: 6), boardID: "Page", boardOffset: PenPoint(x: 5, y: 6),
            nodeID: "Free", index: 1
        )])
    }

    @Test("A node deeper in a board records its own parent and its offset from the board")
    func nestedChild() throws {
        let clip = try PenClip.extract(nodeIDs: ["Fill"], from: PenClipFixture.document())

        #expect(clip.origins?["Fill"] == PenClip.Origin(
            parentID: "Card", offset: PenPoint(x: 0, y: 19), boardID: "Page", boardOffset: PenPoint(x: 10, y: 39),
            nodeID: "Fill", index: 1, width: .fillContainer(fallback: nil)
        ))
    }

    @Test("A root has no parent or board, and measures its offset from the canvas origin")
    func root() throws {
        let clip = try PenClip.extract(nodeIDs: ["Page"], from: PenClipFixture.document())

        #expect(clip.origins == ["Page": PenClip.Origin(
            parentID: nil, offset: nil, boardID: nil, boardOffset: PenPoint(x: 100, y: 200),
            nodeID: "Page", index: 1
        )])
    }

    @Test("A node drawn inside an instance names its board, and a parent no paste can write into")
    func drawnNode() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["BtnI/IcoRef/Icon"], from: source)

        let id = try #require(clip.contentIDs.first)
        let origin = try #require(clip.origins?[id])
        #expect(origin.boardID == "Page")
        #expect(origin.offset == PenPoint(x: 28, y: 0))
        let parentID = try #require(origin.parentID)
        let parent = source.nodes[parentID]
        #expect(parent == nil || parent.map { if case .ref = $0.kind { true } else { false } } == true)
    }

    @Test("The source document's id is what the copy was given, and nothing when it was given none")
    func documentID() throws {
        let source = try PenClipFixture.document()

        #expect(try PenClip.extract(nodeIDs: ["Free"], from: source, documentID: "doc-A").sourceDocumentID == "doc-A")
        #expect(try PenClip.extract(nodeIDs: ["Free"], from: source).sourceDocumentID == nil)
    }

    @Test("Origins and the document id survive the pasteboard's JSON")
    func roundTrip() throws {
        let clip = try PenClip.extract(nodeIDs: ["Free", "Fill"], from: PenClipFixture.document(), documentID: "doc-A")

        let decoded = try JSONDecoder().decode(PenClip.self, from: JSONEncoder().encode(clip))

        #expect(decoded == clip)
        #expect(decoded.origins?.count == 2)
        #expect(decoded.sourceDocumentID == "doc-A")
    }

    @Test("A clip written without origins or a document id still reads, with neither")
    func oldClipDecodes() throws {
        let clip = try PenClip.extract(nodeIDs: ["Free"], from: PenClipFixture.document(), documentID: "doc-A")
        let written = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        #expect(written["origins"] != nil)
        #expect(written["sourceDocumentID"] != nil)
        let old = try JSONSerialization.data(withJSONObject: [
            "contentIDs": clip.contentIDs,
            "document": JSONSerialization.jsonObject(with: JSONEncoder().encode(clip.document)),
        ])

        let decoded = try JSONDecoder().decode(PenClip.self, from: old)

        #expect(decoded.origins == nil)
        #expect(decoded.sourceDocumentID == nil)
        #expect(decoded.contentIDs == ["Free"])
    }
}
