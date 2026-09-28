//
//  RootPlacementMarginTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A root added or copied without coordinates lands clear of every existing root, by
/// ``RootOverlap/margin``.
@MainActor
struct RootPlacementMarginTests {
    // MARK: - Helpers

    /// A document of 100×100 root frames at the given origins.
    private func document(_ origins: [(id: String, x: Double, y: Double)]) -> EditableDocument {
        EditableDocument(from: PenDocument(children: origins.enumerated().map { index, origin in
            PenNode(
                id: origin.id,
                common: PenNodeCommon(name: "Root \(index)", x: .literal(origin.x), y: .literal(origin.y)),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(100), height: .fixed(100), layout: PenLayoutDirection.none
                ))
            )
        }))
    }

    /// A 100×100 frame with no coordinates of its own, ready to be placed.
    private func unplaced(_ id: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: "New"),
            kind: .frame(PenNode.FrameData(
                width: .fixed(100), height: .fixed(100), layout: PenLayoutDirection.none
            ))
        )
    }

    /// The rect a placed node will occupy, from the coordinates placement gave it.
    private func rect(of node: PenNode) throws -> PenRect {
        let x = try #require(node.common.x?.literalValue)
        let y = try #require(node.common.y?.literalValue)
        return PenRect(x: x, y: y, width: 100, height: 100)
    }

    // MARK: - The margin

    @Test("The margin is a named constant, not a number spelled at the call site")
    func marginIsNamed() {
        #expect(RootOverlap.margin == 100)
    }

    // MARK: - Placement

    @Test("An auto-placed root clears every existing root by the margin")
    func placedRootKeepsTheMargin() throws {
        let existing = document([(id: "Aaa01", x: 0, y: 0), (id: "Bbb01", x: 300, y: 0)])
        let placed = BatchApplier.placedAtRoot(unplaced("Ccc01"), in: existing, coordinates: .authored)
        let rect = try rect(of: placed)

        // The rightmost edge is Bbb01's, at 400.
        #expect(rect.x == 400 + RootOverlap.margin)
        for id in existing.rootOrder {
            let other = try #require(existing.computeLayout()[id])
            #expect(rect.x - (other.x + other.width) >= RootOverlap.margin)
        }
    }

    @Test("The margin holds when the existing roots are not in x order")
    func placementIgnoresDeclarationOrder() throws {
        let existing = document([
            (id: "Aaa01", x: 900, y: 0),
            (id: "Bbb01", x: 0, y: 0),
            (id: "Ccc01", x: 400, y: 0),
        ])
        let placed = BatchApplier.placedAtRoot(unplaced("Ddd01"), in: existing, coordinates: .authored)
        let rect = try rect(of: placed)

        let rects = existing.computeLayout()
        for id in existing.rootOrder {
            let other = try #require(rects[id])
            #expect(rect.x - (other.x + other.width) >= RootOverlap.margin)
        }
    }

    @Test("An auto-placed root intersects nothing that is already there")
    func placedRootIntersectsNothing() throws {
        let existing = document([
            (id: "Aaa01", x: 900, y: -500),
            (id: "Bbb01", x: 0, y: 0),
            (id: "Ccc01", x: 400, y: 700),
        ])
        let placed = BatchApplier.placedAtRoot(unplaced("Ddd01"), in: existing, coordinates: .authored)
        let mine = try RootOverlap.Root(id: "Ddd01", name: "New", rect: rect(of: placed))

        let rects = existing.computeLayout()
        let others = try existing.rootOrder.map { id in
            try RootOverlap.Root(id: id, name: nil, rect: #require(rects[id]))
        }
        #expect(RootOverlap.overlaps(among: others + [mine]).isEmpty)
    }

    @Test("A copied root is placed even though it carries the source's coordinates")
    func copiedRootIsPlaced() throws {
        let existing = document([(id: "Aaa01", x: 0, y: 0)])
        var carried = unplaced("Bbb01")
        carried.common.x = .literal(0)
        carried.common.y = .literal(0)

        let placed = BatchApplier.placedAtRoot(carried, in: existing, coordinates: .copied)
        #expect(try rect(of: placed).x == 200)
    }

    @Test("An authored root that says where it goes is left exactly there")
    func authoredCoordinatesWin() {
        let existing = document([(id: "Aaa01", x: 0, y: 0)])
        var authored = unplaced("Bbb01")
        authored.common.x = .literal(10)

        let placed = BatchApplier.placedAtRoot(authored, in: existing, coordinates: .authored)
        #expect(placed.common.x?.literalValue == 10)
        #expect(placed.common.y == nil)
    }

    @Test("The first root in an empty document is left where it is")
    func firstRootIsNotMoved() {
        let empty = EditableDocument(from: PenDocument(children: []))
        let placed = BatchApplier.placedAtRoot(unplaced("Aaa01"), in: empty, coordinates: .authored)
        #expect(placed.common.x == nil)
        #expect(placed.common.y == nil)
    }
}
