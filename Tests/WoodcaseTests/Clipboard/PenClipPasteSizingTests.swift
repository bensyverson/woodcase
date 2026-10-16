//
//  PenClipPasteSizingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A pasted copy keeps the size it was drawn at where its new parent does not lay it
/// out, and fills again where one does (Ben's ruling of 2026-10-15, Penumbra spec §4):
/// the clip records a `fill_container` dimension's original sizing in its
/// ``PenClip/Origin``, and the planner decides per destination.
///
/// `Fill` fills the width of the vertical stack `Card` (200 wide) and is 10 high.
struct PenClipPasteSizingTests {
    private func fillClip() throws -> (PenClip, EditableDocument) {
        let source = try PenClipFixture.document()
        return try (PenClip.extract(nodeIDs: ["Fill"], from: source, documentID: "doc-A"), source)
    }

    private func width(_ plan: PastePlan) throws -> AnyCodable? {
        let insert = try #require(PasteFixture.contentInserts(plan).first)
        return try NodePropertyCodec.value(at: "kind.width", of: insert.node)
    }

    @Test("The clip draws the copy at its drawn size and records the fill it had")
    func clipRecordsFill() throws {
        let (clip, _) = try fillClip()

        let root = try #require(clip.document.children.first { $0.id == "Fill" })
        #expect(try (NodePropertyCodec.value(at: "kind.width", of: root) as AnyCodable?).points == 200)
        #expect(clip.origins?["Fill"]?.width == .fillContainer(fallback: nil))
        #expect(clip.origins?["Fill"]?.height == nil, "a fixed height needs no record")
    }

    @Test("Back into the stack it came from, the copy fills again")
    func whereCopiedRefills() throws {
        let (clip, source) = try fillClip()

        #expect(try width(clip.plan(into: source, at: .whereCopied(documentID: "doc-A"))) == .string("fill_container"))
    }

    @Test("Into or beside a node in any stack, the copy fills again")
    func stackTargetsRefill() throws {
        let (clip, source) = try fillClip()

        #expect(try width(clip.plan(into: source, at: .inside(containerID: "Card"))) == .string("fill_container"))
        #expect(try width(clip.plan(into: source, at: .after(siblingID: "BtnI"))) == .string("fill_container"))
    }

    @Test("Into a parent that does not lay it out, the copy keeps its drawn size")
    func freeTargetsKeepDrawnSize() throws {
        let (clip, source) = try fillClip()

        #expect(try width(clip.plan(into: source, at: .inside(containerID: "Page"))).points == 200)
        #expect(try width(clip.plan(into: source, at: .atBoardOffset(in: "Page"))).points == 200)
        #expect(try width(clip.plan(into: source, at: .inPlace)).points == 200)
    }

    @Test("A fill with a fallback comes back with its fallback")
    func fallbackKept() throws {
        let source = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Col", "type": "frame", "x": 0, "y": 0, "width": 300, "height": 100, "layout": "vertical",
            "children": [ { "id": "Bar", "type": "rectangle", "width": "fill_container(40)", "height": 10 } ] }
        ] }
        """)
        let clip = try PenClip.extract(nodeIDs: ["Bar"], from: source, documentID: "doc-A")

        #expect(try width(clip.plan(into: source, at: .whereCopied(documentID: "doc-A"))) == .string("fill_container(40)"))
    }

    @Test("A root that fills is fixed at its drawn size where it is not laid out, and kept in a stack")
    func rootFill() throws {
        let source = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Wide", "type": "frame", "x": 0, "y": 0, "width": "fill_container(150)", "height": 20, "layout": "none" },
          { "id": "Free", "type": "frame", "x": 500, "y": 0, "width": 300, "height": 300, "layout": "none" },
          { "id": "Col", "type": "frame", "x": 900, "y": 0, "width": 300, "height": 300, "layout": "vertical" }
        ] }
        """)
        let clip = try PenClip.extract(nodeIDs: ["Wide"], from: source)

        #expect(try width(clip.plan(into: source, at: .inside(containerID: "Free"))).points == 150)
        #expect(try width(clip.plan(into: source, at: .inside(containerID: "Col"))) == .string("fill_container(150)"))
    }

    @Test("The recorded sizing survives the pasteboard's JSON")
    func roundTrip() throws {
        let (clip, _) = try fillClip()

        let decoded = try JSONDecoder().decode(PenClip.self, from: JSONEncoder().encode(clip))

        #expect(decoded.origins?["Fill"]?.width == .fillContainer(fallback: nil))
    }
}

private extension AnyCodable? {
    /// The number a sizing holds, written as an integer or not.
    var points: Double? {
        switch self {
        case let .double(value)?: value
        case let .int(value)?: Double(value)
        default: nil
        }
    }
}
