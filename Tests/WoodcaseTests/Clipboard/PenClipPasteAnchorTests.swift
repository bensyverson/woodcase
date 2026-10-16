//
//  PenClipPasteAnchorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The targets that place a paste by a point: ``PasteTarget/at(topLeft:in:)``,
/// ``PasteTarget/centered(on:in:)`` and ``PasteTarget/atInnerTopLeft(of:)``. Each moves
/// the copies together, keeping their arrangement, and lands exactly — never re-centered
/// to fit the container.
///
/// `Free` is a 10 × 10 rectangle drawn at (105, 206); `Card` is 200 × 100 at (110, 220),
/// so the two together span (105, 206)–(310, 320). `Card` comes first in document order,
/// so first in the clip.
struct PenClipPasteAnchorTests {
    private func clip(_ ids: [String]) throws -> PenClip {
        try PenClip.extract(nodeIDs: ids, from: PenClipFixture.document())
    }

    private static let target = """
    { "version": "2.17", "children": [
      { "id": "Far", "type": "frame", "x": 1000, "y": 1000, "width": 100, "height": 100, "layout": "none" },
      { "id": "Pad", "type": "frame", "x": 0, "y": 2000, "width": 100, "height": 100, "layout": "none",
        "padding": [4, 8] },
      { "id": "Col", "type": "frame", "x": 0, "y": 3000, "width": 100, "height": 100, "layout": "vertical" }
    ] }
    """

    private func inserts(_ ids: [String], at target: PasteTarget) throws -> [EditOperation.InsertNode] {
        try PasteFixture.contentInserts(clip(ids).plan(into: PasteFixture.document(Self.target), at: target))
    }

    @Test("At a point on the canvas, the copies' top-left corner lands on it, as roots")
    func topLeftOnCanvas() throws {
        let inserts = try inserts(["Free", "Card"], at: .at(topLeft: PenPoint(x: 0, y: 0), in: nil))

        #expect(inserts.map(\.parentID) == [nil, nil])
        #expect(inserts.map(\.node.common.x) == [.literal(5), .literal(0)])
        #expect(inserts.map(\.node.common.y) == [.literal(14), .literal(0)])
    }

    @Test("At a point in a container, the corner lands there, written in its coordinates")
    func topLeftInContainer() throws {
        let insert = try #require(inserts(["Free"], at: .at(topLeft: PenPoint(x: 1010, y: 1020), in: "Far")).first)

        #expect(insert.parentID == "Far")
        #expect(insert.node.common.x == .literal(10))
        #expect(insert.node.common.y == .literal(20))
    }

    @Test("At a point that misses the container, the copies still land on it")
    func topLeftMissingContainer() throws {
        let insert = try #require(inserts(["Free"], at: .at(topLeft: PenPoint(x: 5000, y: 5000), in: "Far")).first)

        #expect(insert.node.common.x == .literal(4000))
        #expect(insert.node.common.y == .literal(4000))
    }

    @Test("Centered on a canvas point, the copies' bounds center there, as roots")
    func centeredOnCanvas() throws {
        let inserts = try inserts(["Free", "Card"], at: .centered(on: PenPoint(x: 0, y: 0), in: nil))

        #expect(inserts.map(\.parentID) == [nil, nil])
        #expect(inserts.map(\.node.common.x) == [.literal(-97.5), .literal(-102.5)])
        #expect(inserts.map(\.node.common.y) == [.literal(-43), .literal(-57)])
    }

    @Test("Centered on a point in a container, the copies center there, in its coordinates")
    func centeredInContainer() throws {
        let insert = try #require(inserts(["Free"], at: .centered(on: PenPoint(x: 1050, y: 1050), in: "Far")).first)

        #expect(insert.parentID == "Far")
        #expect(insert.node.common.x == .literal(45))
        #expect(insert.node.common.y == .literal(45))
    }

    @Test("At the inner top-left, the copies' corner sits inside the padding")
    func innerTopLeft() throws {
        let inserts = try inserts(["Free", "Card"], at: .atInnerTopLeft(of: "Pad"))

        #expect(inserts.map(\.parentID) == ["Pad", "Pad"])
        #expect(inserts.map(\.node.common.x) == [.literal(13), .literal(8)])
        #expect(inserts.map(\.node.common.y) == [.literal(18), .literal(4)])
    }

    @Test("In a stack, every point target joins the flow")
    func stackFlows() throws {
        for target in [
            PasteTarget.at(topLeft: PenPoint(x: 0, y: 3000), in: "Col"),
            .centered(on: PenPoint(x: 0, y: 3000), in: "Col"),
            .atInnerTopLeft(of: "Col"),
        ] {
            let insert = try #require(inserts(["Free"], at: target).first)
            #expect(insert.parentID == "Col")
            #expect(insert.node.common.x == nil)
            #expect(insert.node.common.y == nil)
        }
    }

    @Test("A point target names a container the document stores and can hold children")
    func refusals() throws {
        let copied = try clip(["Free"])
        let target = try PasteFixture.document(Self.target)

        #expect(throws: PasteError.targetNotFound(id: "Ghost")) {
            try copied.plan(into: target, at: .at(topLeft: PenPoint(x: 0, y: 0), in: "Ghost"))
        }
        #expect(throws: PasteError.targetNotFound(id: "Ghost")) {
            try copied.plan(into: target, at: .atInnerTopLeft(of: "Ghost"))
        }
    }
}
