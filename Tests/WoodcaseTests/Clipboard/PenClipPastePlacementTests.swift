//
//  PenClipPastePlacementTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Where ``PenClip/plan(into:at:)`` puts the copies for each ``PasteTarget``, where it
/// puts the definitions they bring, and what it refuses.
///
/// `Free` is a 10 × 10 rectangle drawn at (105, 206) on the canvas: (5, 6) inside
/// `Page`, which sits at (100, 200).
struct PenClipPastePlacementTests {
    private func freeClip() throws -> (PenClip, EditableDocument) {
        let source = try PenClipFixture.document()
        return try (PenClip.extract(nodeIDs: ["Free"], from: source), source)
    }

    @Test("In place, the copies are roots at the coordinates they were copied from")
    func inPlace() throws {
        let (clip, source) = try freeClip()

        let insert = try #require(PasteFixture.inserts(clip.plan(into: source, at: .inPlace)).first)

        #expect(insert.parentID == nil)
        #expect(insert.node.common.x == .literal(105))
        #expect(insert.node.common.y == .literal(206))
    }

    @Test("On the canvas, the copies are roots centered on the point")
    func canvasCenter() throws {
        let (clip, source) = try freeClip()

        let plan = try clip.plan(into: source, at: .centered(on: PenPoint(x: 0, y: 0), in: nil))

        let insert = try #require(PasteFixture.inserts(plan).first)
        #expect(insert.parentID == nil)
        #expect(insert.node.common.x == .literal(-5))
        #expect(insert.node.common.y == .literal(-5))
    }

    @Test("Inside a free container, the copies keep their canvas position, in its coordinates")
    func insideFreeContainer() throws {
        let (clip, source) = try freeClip()

        let insert = try #require(PasteFixture.inserts(clip.plan(into: source, at: .inside(containerID: "Page"))).first)

        #expect(insert.parentID == "Page")
        #expect(insert.index == nil)
        #expect(insert.node.common.x == .literal(5))
        #expect(insert.node.common.y == .literal(6))
    }

    @Test("Inside another free container, the copies keep the offset they had in their parent")
    func insideOtherContainerKeepsOffset() throws {
        let (clip, _) = try freeClip()
        let target = try PasteFixture.document(Self.farContainer)

        let insert = try #require(PasteFixture.inserts(clip.plan(into: target, at: .inside(containerID: "Far"))).first)

        #expect(insert.node.common.x == .literal(5))
        #expect(insert.node.common.y == .literal(6))
    }

    @Test("Inside a container too small for the offset, the copies are centered in it")
    func offsetMissesSmallContainer() throws {
        let (clip, _) = try freeClip()
        let target = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Tiny", "type": "frame", "x": 105, "y": 206, "width": 4, "height": 4, "layout": "none" }
        ] }
        """)

        let insert = try #require(PasteFixture.inserts(clip.plan(into: target, at: .inside(containerID: "Tiny"))).first)

        #expect(insert.node.common.x == .literal(-3))
        #expect(insert.node.common.y == .literal(-3))
    }

    /// A free container far from where `Free` was drawn.
    static let farContainer = """
    { "version": "2.17", "children": [
      { "id": "Far", "type": "frame", "x": 1000, "y": 1000, "width": 100, "height": 100, "layout": "none" }
    ] }
    """

    @Test("A clip without offsets keeps the canvas position, and is centered in a container it would miss")
    func insideFarContainer() throws {
        let (copied, _) = try freeClip()
        let clip = PenClip(document: copied.document, contentIDs: copied.contentIDs)
        let target = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Far", "type": "frame", "x": 1000, "y": 1000, "width": 100, "height": 100, "layout": "none" }
        ] }
        """)

        let insert = try #require(PasteFixture.inserts(clip.plan(into: target, at: .inside(containerID: "Far"))).first)

        #expect(insert.node.common.x == .literal(45))
        #expect(insert.node.common.y == .literal(45))
    }

    @Test("After a node in a free container, the copies sit to its right, right after it")
    func afterInFreeContainer() throws {
        let (clip, source) = try freeClip()

        let insert = try #require(PasteFixture.inserts(clip.plan(into: source, at: .after(siblingID: "Free"))).first)

        #expect(insert.parentID == "Page")
        #expect(insert.index == 2)
        #expect(insert.node.common.x == .literal(5 + 10 + PenClip.besideGap))
        #expect(insert.node.common.y == .literal(6))
    }

    @Test("After a root, the copies are roots to its right, a canvas margin away")
    func afterRoot() throws {
        let (clip, source) = try freeClip()
        let page = try #require(source.rootOrder.firstIndex(of: "Page"))

        let insert = try #require(PasteFixture.inserts(clip.plan(into: source, at: .after(siblingID: "Page"))).first)

        #expect(insert.parentID == nil)
        #expect(insert.index == page + 1)
        #expect(insert.node.common.x == .literal(500 + RootOverlap.margin))
        #expect(insert.node.common.y == .literal(200))
    }

    @Test("After a node in a stack, the copies join the flow right after it")
    func afterInStack() throws {
        let (clip, source) = try freeClip()

        let insert = try #require(PasteFixture.inserts(clip.plan(into: source, at: .after(siblingID: "BtnI"))).first)

        #expect(insert.parentID == "Card")
        #expect(insert.index == 1)
        #expect(insert.node.common.x == nil)
        #expect(insert.node.common.y == nil)
    }

    @Test("Definitions the target lacks land as roots, past everything on its canvas")
    func definitionsLandPastTheRoots() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: PenClipFixture.document())
        let target = try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Art", "type": "frame", "x": 0, "y": 40, "width": 300, "height": 100, "layout": "none" }
        ] }
        """)

        let plan = try clip.plan(into: target, at: .inside(containerID: "Art"))

        let definitions = PasteFixture.inserts(plan).filter { $0.node.common.reusable == true }
        #expect(definitions.count == 2)
        #expect(definitions.allSatisfy { $0.parentID == nil })
        #expect(definitions.first?.node.common.x == .literal(300 + RootOverlap.margin))
        #expect(definitions.allSatisfy { $0.node.common.y == .literal(40) })
        let xs = definitions.compactMap { $0.node.common.x?.literalValue }
        #expect(xs == xs.sorted() && Set(xs).count == xs.count)
    }

    @Test("Every refusal names what it refused")
    func refusals() throws {
        let (clip, source) = try freeClip()
        let broken = PenClip(document: clip.document, contentIDs: ["Nope"])

        #expect(throws: PasteError.targetNotFound(id: "Ghost")) {
            try clip.plan(into: source, at: .inside(containerID: "Ghost"))
        }
        #expect(throws: PasteError.targetNotFound(id: "Ghost")) {
            try clip.plan(into: source, at: .after(siblingID: "Ghost"))
        }
        #expect(throws: PasteError.notAContainer(id: "Free")) {
            try clip.plan(into: source, at: .inside(containerID: "Free"))
        }
        #expect(throws: PasteError.notAContainer(id: "BtnI")) {
            try clip.plan(into: source, at: .inside(containerID: "BtnI"))
        }
        #expect(throws: PasteError.contentNotInClip(id: "Nope")) {
            try broken.plan(into: source, at: .inPlace)
        }
    }
}
