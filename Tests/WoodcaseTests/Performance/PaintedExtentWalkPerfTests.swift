//
//  PaintedExtentWalkPerfTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

extension PerformanceBudgets {
    /// Measures what RapidPro's `RenderNodeProducer` and Penumbra's `HitShapeBuilder`
    /// actually pay for `paintedExtent`: not one call on the document's root, but one
    /// call **per node**, each walking its own subtree — so a text or an icon nested
    /// under several unclipped ancestors is measured again by every ancestor's own call,
    /// not once.
    ///
    /// No fixed ceiling: this is a before/after record, not a regression gate. The
    /// figures it prints are what `project/2026-09-28-geometry-model.md`'s leaf note
    /// quotes for text and icon ink (`textInkBounds`/`iconInkBounds`, each a Core Text
    /// layout) against the box-only answer `main` gave before them.
    @MainActor
    struct PaintedExtentWalkTests {
        @Test("paintedExtent for every node of the largest real fixture, called once per node")
        func paintedExtentWalkOfLargestFixture() async throws {
            let url = try PerformanceFixture.largestBundled()
            let data = try Data(contentsOf: url)
            let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
            let rects = PenLayoutEngine.layout(document)
            let entries = Self.walk(document, rects: rects)

            let sample = try await PerformanceSample.measure(repetitions: 5) {
                for (node, rect) in entries {
                    _ = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
                }
            }
            print(
                "PAINTED-EXTENT-WALK | \(url.lastPathComponent) | nodes \(entries.count)"
                    + " | min \(PerformanceBudget.milliseconds(sample.best))"
                    + " | samples \(sample.summary)"
            )
        }

        /// Every node with a settled rect, and that rect — a work-list walk, so a caller
        /// hands `paintedExtent` the node it already has in hand, exactly as
        /// `RenderNodeProducer` and `HitShapeBuilder` do, rather than a second lookup by
        /// id that would put its own cost into the measurement.
        private static func walk(_ document: PenDocument, rects: [String: PenRect]) -> [(PenNode, PenRect)] {
            var entries: [(PenNode, PenRect)] = []
            var pending = document.children
            while let node = pending.popLast() {
                if let rect = rects[node.id] {
                    entries.append((node, rect))
                }
                pending.append(contentsOf: node.kind.inlineChildren)
            }
            return entries
        }
    }
}
