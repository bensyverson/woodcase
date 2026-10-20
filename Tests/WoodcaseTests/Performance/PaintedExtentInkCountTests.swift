//
//  PaintedExtentInkCountTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Counts the text inks a painted-extent pass over one artboard of Penumbra's perf board
/// (``PerfBoardFixture``) asks for and lays out: what RapidPro's render stage and
/// Penumbra's hit shapes each pay per run. A count, not a time, so it gates on any
/// machine.
struct PaintedExtentInkCountTests {
    @Test("A call per node asks for a text's ink once per unclipped ancestor; one walk asks once per text")
    func oneWalkAsksOncePerText() throws {
        let document = try PerfBoardFixture.document()
        let rects = PenLayoutEngine.layout(document)

        let perNode = CostCounter()
        CostCounter.$current.withValue(perNode) {
            var pending = document.children
            while let node = pending.popLast() {
                guard let rect = rects[node.id] else { continue }
                _ = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
                pending.append(contentsOf: node.kind.inlineChildren)
            }
        }
        let oneWalk = CostCounter()
        let extents = CostCounter.$current.withValue(oneWalk) {
            PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
        }

        #expect(extents.count == PerfBoardFixture.nodeCount)
        #expect(perNode.count(of: .textInkLookup) == PerfBoardFixture.perNodeInkLookups)
        #expect(oneWalk.count(of: .textInkLookup) == PerfBoardFixture.textCount)
        print(
            "PAINTED-EXTENT-INK | perf board artboard | nodes \(extents.count)"
                + " | ink lookups per node \(perNode.count(of: .textInkLookup))"
                + " | one walk \(oneWalk.count(of: .textInkLookup))"
        )
    }

    @Test("An unchanged text keeps its ink across walks: the second walk lays out no text")
    func inkIsKeptAcrossWalks() throws {
        let document = try PerfBoardFixture.document()
        let rects = PenLayoutEngine.layout(document)
        let cache = TextInkCache(fontGeneration: { 0 })

        let first = CostCounter(), second = CostCounter()
        let (before, after) = TextInkCache.$current.withValue(cache) {
            let before = CostCounter.$current.withValue(first) {
                PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
            }
            let after = CostCounter.$current.withValue(second) {
                PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
            }
            return (before, after)
        }

        #expect(before == after)
        // Twenty "Open" labels share one key, so even the first walk lays out fewer texts
        // than it holds.
        #expect(first.count(of: .textInkLayout) > 0)
        #expect(first.count(of: .textInkLayout) < PerfBoardFixture.textCount)
        #expect(second.count(of: .textInkLookup) == PerfBoardFixture.textCount)
        #expect(second.count(of: .textInkLayout) == 0)
        print(
            "PAINTED-EXTENT-INK-CACHE | perf board artboard | first walk lays out \(first.count(of: .textInkLayout))"
                + " | second \(second.count(of: .textInkLayout))"
        )
    }
}
