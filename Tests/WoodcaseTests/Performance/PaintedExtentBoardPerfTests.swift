//
//  PaintedExtentBoardPerfTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
@testable import Woodcase

extension PerformanceBudgets {
    /// Times a painted-extent pass over one artboard of Penumbra's perf board
    /// (``PerfBoardFixture``) three ways: a `paintedExtent` call per node with no ink kept
    /// — what RapidPro's render stage and Penumbra's hit shapes each paid before
    /// ``PenLayoutEngine/paintedExtents(in:layoutRects:)`` — then one walk with no ink
    /// kept, then one walk with every ink already in ``TextInkCache``, an editor's steady
    /// state after an edit that changed no text.
    ///
    /// No fixed ceiling: a before/after record for <doc:WoodcasePerformance>'s "Painted
    /// extents of a run", not a regression gate; ``PaintedExtentInkCountTests`` gates the
    /// counts.
    @MainActor
    struct PaintedExtentBoardTests {
        @Test("paintedExtent per node vs. one walk, cold and warm, on a perf-board artboard")
        func perNodeVersusOneWalk() async throws {
            let document = try PerfBoardFixture.document()
            let rects = PenLayoutEngine.layout(document)

            // A font generation that moves on every read keeps no ink: the path before the cache.
            let tick = Mutex(0)
            let uncached = TextInkCache(fontGeneration: { tick.withLock { $0 += 1; return $0 } })
            let warm = TextInkCache(fontGeneration: { 0 })
            TextInkCache.$current.withValue(warm) {
                _ = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
            }

            let perNode = try await PerformanceSample.measure(repetitions: 7) {
                TextInkCache.$current.withValue(uncached) {
                    var pending = document.children
                    while let node = pending.popLast() {
                        guard let rect = rects[node.id] else { continue }
                        _ = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
                        pending.append(contentsOf: node.kind.inlineChildren)
                    }
                }
            }
            let oneWalkCold = try await PerformanceSample.measure(repetitions: 7) {
                TextInkCache.$current.withValue(uncached) {
                    _ = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
                }
            }
            let oneWalkWarm = try await PerformanceSample.measure(repetitions: 7) {
                TextInkCache.$current.withValue(warm) {
                    _ = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
                }
            }
            print(
                "PAINTED-EXTENT-BOARD | perf board artboard | nodes \(PerfBoardFixture.nodeCount)"
                    + " | per node, no cache \(PerformanceBudget.milliseconds(perNode.best))"
                    + " | one walk, no cache \(PerformanceBudget.milliseconds(oneWalkCold.best))"
                    + " | one walk, warm cache \(PerformanceBudget.milliseconds(oneWalkWarm.best))"
            )
        }
    }
}
