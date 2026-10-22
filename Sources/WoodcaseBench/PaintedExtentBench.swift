//
//  PaintedExtentBench.swift
//  WoodcaseBench
//

import Foundation
import Synchronization
import Woodcase
import WoodcasePerfFixtures

/// What painted extents cost, two ways.
///
/// - `painted-extent-walk`: a `paintedExtent` call per node of the largest real fixture,
///   each walking its own subtree, which is what RapidPro's `RenderNodeProducer` and
///   Penumbra's `HitShapeBuilder` paid before the one-walk pass. The figures are what
///   `project/2026-09-28-geometry-model.md` quotes for text and icon ink.
/// - `painted-extent-board`: one artboard of Penumbra's perf board (``PerfBoardFixture``)
///   three ways: a call per node with no ink kept, one walk with no ink kept, and one walk
///   with every ink already in the text-ink cache, an editor's steady state after an edit
///   that changed no text (<doc:WoodcasePerformance>'s "Painted extents of a run").
///
/// `PaintedExtentInkCountTests` gates the counts.
enum PaintedExtentBench {
    /// The per-node walk over `woodcase-app.pen`.
    static let walk = Bench(
        name: "painted-extent-walk",
        summary: "paintedExtent called once per node of woodcase-app.pen",
        run: { _ in try runWalk() }
    )

    /// The perf-board artboard, per node and one walk, cold and warm.
    static let board = Bench(
        name: "painted-extent-board",
        summary: "paintedExtent per node vs. one walk, cold and warm cache, on a perf-board artboard",
        run: { _ in try runBoard() }
    )

    private static func runWalk() throws {
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(
            PenParser.parse(Data(contentsOf: PerfFixtureFile.woodcaseApp.url))
        ))
        let rects = PenLayoutEngine.layout(document)
        let entries = PenNode.flatten(document.children).compactMap { node in rects[node.id].map { (node, $0) } }
        print("PROBE painted-extent walk woodcase-app nodes \(entries.count)")
        BenchClock.measure("painted-extent walk woodcase-app per node", runs: 5) {
            for (node, rect) in entries {
                _ = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
            }
        }
    }

    private static func runBoard() throws {
        let document = try PerfBoardFixture.document()
        let rects = PenLayoutEngine.layout(document)
        let entries = PenNode.flatten(document.children).compactMap { node in rects[node.id].map { (node, $0) } }

        // A font generation that moves on every read keeps no ink: the path before the cache.
        let tick = Mutex(0)
        let uncached = TextInkCache(fontGeneration: { tick.withLock { $0 += 1; return $0 } })
        let warm = TextInkCache(fontGeneration: { 0 })
        TextInkCache.$current.withValue(warm) {
            _ = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
        }

        print("PROBE painted-extent board nodes \(PerfBoardFixture.nodeCount)")
        BenchClock.measure("painted-extent board per node, no cache", runs: 7) {
            TextInkCache.$current.withValue(uncached) {
                for (node, rect) in entries {
                    _ = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
                }
            }
        }
        BenchClock.measure("painted-extent board one walk, no cache", runs: 7) {
            TextInkCache.$current.withValue(uncached) {
                _ = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
            }
        }
        BenchClock.measure("painted-extent board one walk, warm cache", runs: 7) {
            TextInkCache.$current.withValue(warm) {
                _ = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
            }
        }
    }
}
