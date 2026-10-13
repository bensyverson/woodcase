//
//  PenClipPlacementTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/extract(nodeIDs:from:)`` puts each copied root where it was drawn on the
/// canvas, at the size it was drawn.
struct PenClipPlacementTests {
    @Test("A nested node comes out at its canvas position")
    func nestedNodeAtCanvasPosition() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Free", "Card"], from: document)

        let roots = PenClipFixture.index(clip.document.children)
        #expect(roots["Free"]?.common.x == .literal(105))
        #expect(roots["Free"]?.common.y == .literal(206))
        #expect(roots["Card"]?.common.x == .literal(110))
        #expect(roots["Card"]?.common.y == .literal(220))
    }

    @Test("A root keeps its own position, and its children theirs")
    func rootKeepsPosition() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Page"], from: document)

        let root = try #require(clip.document.children.first)
        #expect(try root == (document.materializeSubtree(rootID: "Page")))
    }

    @Test("A node a stack placed comes out where the stack put it")
    func stackChildAtCanvasPosition() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI/Lbl"], from: document)

        let root = try #require(clip.document.children.first)
        #expect(root.common.x == .literal(110))
        #expect(root.common.y == .literal(220))
    }

    @Test("A node that filled its container comes out at the size it was drawn")
    func fillContainerIsFixed() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Fill"], from: document)

        let root = try #require(clip.document.children.first)
        guard case let .rectangle(data) = root.kind else {
            Issue.record("the rectangle did not come out as one")
            return
        }
        #expect(data.width == .fixed(200))
        #expect(data.height == .fixed(10))
    }
}
