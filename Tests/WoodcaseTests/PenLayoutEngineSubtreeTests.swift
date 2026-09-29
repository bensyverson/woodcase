//
//  PenLayoutEngineSubtreeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PenLayoutEngineSubtreeTests {
    // MARK: - Helpers

    /// Creates a nested document:
    /// root-frame (fixed 400x300, horizontal, gap: 10, padding: 10)
    /// ├── inner-container (fixed 180x280, vertical, gap: 5)
    /// │   ├── child-a (fixed 180x50)
    /// │   ├── child-b (fixed 180x50)
    /// │   └── child-c (fillContainer width, fixed 50 height)
    /// └── sibling-rect (fixed 180x280)
    private func makeNestedDocument() -> PenDocument {
        PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "root-frame",
                    common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(400), height: .fixed(300),
                        layout: .horizontal,
                        gap: .literal(10),
                        padding: .uniform(.literal(10)),
                        children: [
                            PenNode(
                                id: "inner-container",
                                common: PenNodeCommon(),
                                kind: .frame(PenNode.FrameData(
                                    width: .fixed(180), height: .fixed(280),
                                    layout: .vertical,
                                    gap: .literal(5),
                                    children: [
                                        PenNode(
                                            id: "child-a",
                                            common: PenNodeCommon(),
                                            kind: .rectangle(PenNode.RectangleData(
                                                width: .fixed(180), height: .fixed(50)
                                            ))
                                        ),
                                        PenNode(
                                            id: "child-b",
                                            common: PenNodeCommon(),
                                            kind: .rectangle(PenNode.RectangleData(
                                                width: .fixed(180), height: .fixed(50)
                                            ))
                                        ),
                                        PenNode(
                                            id: "child-c",
                                            common: PenNodeCommon(),
                                            kind: .rectangle(PenNode.RectangleData(
                                                width: .fillContainer(fallback: nil), height: .fixed(50)
                                            ))
                                        ),
                                    ]
                                ))
                            ),
                            PenNode(
                                id: "sibling-rect",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(180), height: .fixed(280)
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )
    }

    private func assertRectEqual(
        _ actual: PenRect,
        _ expected: PenRect,
        id: String,
        tolerance: Double = 0.5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            abs(actual.x - expected.x) < tolerance,
            "x mismatch for \(id): got \(actual.x), expected \(expected.x)",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(actual.y - expected.y) < tolerance,
            "y mismatch for \(id): got \(actual.y), expected \(expected.y)",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(actual.width - expected.width) < tolerance,
            "width mismatch for \(id): got \(actual.width), expected \(expected.width)",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(actual.height - expected.height) < tolerance,
            "height mismatch for \(id): got \(actual.height), expected \(expected.height)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Tests

    @Test("Subtree layout matches full layout for inner container")
    func subtreeMatchesFullLayout() {
        let doc = makeNestedDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        let subtreeRects = PenLayoutEngine.layoutSubtree(
            rootID: "inner-container",
            in: doc,
            existingRects: fullRects
        )

        for (id, subtreeRect) in subtreeRects {
            guard let fullRect = fullRects[id] else {
                Issue.record("Full layout missing rect for \(id)")
                continue
            }
            assertRectEqual(subtreeRect, fullRect, id: id)
        }
    }

    @Test("Only subtree rects are returned")
    func onlySubtreeRectsReturned() {
        let doc = makeNestedDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        let subtreeRects = PenLayoutEngine.layoutSubtree(
            rootID: "inner-container",
            in: doc,
            existingRects: fullRects
        )

        let expectedKeys: Set = ["inner-container", "child-a", "child-b", "child-c"]
        #expect(Set(subtreeRects.keys) == expectedKeys)
    }

    @Test("Top-level node as subtree root matches full layout")
    func topLevelNodeAsRoot() {
        let doc = makeNestedDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        let subtreeRects = PenLayoutEngine.layoutSubtree(
            rootID: "root-frame",
            in: doc,
            existingRects: fullRects
        )

        // Should contain all nodes
        #expect(subtreeRects.count == fullRects.count)
        for (id, subtreeRect) in subtreeRects {
            guard let fullRect = fullRects[id] else {
                Issue.record("Full layout missing rect for \(id)")
                continue
            }
            assertRectEqual(subtreeRect, fullRect, id: id)
        }
    }

    @Test("Leaf node as subtree root returns single rect")
    func leafNodeAsRoot() throws {
        let doc = makeNestedDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        let subtreeRects = PenLayoutEngine.layoutSubtree(
            rootID: "sibling-rect",
            in: doc,
            existingRects: fullRects
        )

        #expect(subtreeRects.count == 1)
        #expect(subtreeRects.keys.contains("sibling-rect"))
        let subtreeRect = try #require(subtreeRects["sibling-rect"])
        let fullRect = try #require(fullRects["sibling-rect"])
        assertRectEqual(subtreeRect, fullRect, id: "sibling-rect")
    }

    @Test("Absolute child inside flex container matches full layout")
    func absoluteChildInFlex() {
        let doc = PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "root-frame",
                    common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(400), height: .fixed(300),
                        layout: .horizontal,
                        gap: .literal(10),
                        padding: .uniform(.literal(10)),
                        children: [
                            PenNode(
                                id: "inner-container",
                                common: PenNodeCommon(),
                                kind: .frame(PenNode.FrameData(
                                    width: .fixed(180), height: .fixed(280),
                                    layout: .vertical,
                                    gap: .literal(5),
                                    children: [
                                        PenNode(
                                            id: "flow-child",
                                            common: PenNodeCommon(),
                                            kind: .rectangle(PenNode.RectangleData(
                                                width: .fixed(180), height: .fixed(50)
                                            ))
                                        ),
                                        PenNode(
                                            id: "absolute-child",
                                            common: PenNodeCommon(
                                                x: .literal(20),
                                                y: .literal(30),
                                                layoutPosition: .absolute
                                            ),
                                            kind: .rectangle(PenNode.RectangleData(
                                                width: .fixed(60), height: .fixed(40)
                                            ))
                                        ),
                                    ]
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )

        let fullRects = PenLayoutEngine.layout(doc)
        let subtreeRects = PenLayoutEngine.layoutSubtree(
            rootID: "inner-container",
            in: doc,
            existingRects: fullRects
        )

        let expectedKeys: Set = ["inner-container", "flow-child", "absolute-child"]
        #expect(Set(subtreeRects.keys) == expectedKeys)

        for (id, subtreeRect) in subtreeRects {
            guard let fullRect = fullRects[id] else {
                Issue.record("Full layout missing rect for \(id)")
                continue
            }
            assertRectEqual(subtreeRect, fullRect, id: id)
        }
    }

    @Test("Performance: 20 flex children layout completes quickly")
    @MainActor
    func performanceWith20Children() async throws {
        var children: [PenNode] = []
        for i in 0 ..< 20 {
            children.append(PenNode(
                id: "perf-child-\(i)",
                common: PenNodeCommon(),
                kind: .rectangle(PenNode.RectangleData(
                    width: .fillContainer(fallback: nil), height: .fixed(30)
                ))
            ))
        }

        let doc = PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "perf-root",
                    common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(400), height: .fixed(800),
                        layout: .vertical,
                        gap: .literal(5),
                        padding: .uniform(.literal(10)),
                        children: [
                            PenNode(
                                id: "perf-container",
                                common: PenNodeCommon(),
                                kind: .frame(PenNode.FrameData(
                                    width: .fixed(380), height: .fixed(780),
                                    layout: .vertical,
                                    gap: .literal(2),
                                    children: children
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )

        let fullRects = PenLayoutEngine.layout(doc)

        // Warmup pass to avoid cold-start JIT/cache effects
        _ = PenLayoutEngine.layoutSubtree(
            rootID: "perf-container",
            in: doc,
            existingRects: fullRects
        )

        // `layoutSubtree` is the primitive behind 120Hz interactive editing (drag-resizing
        // a flex container; see 2205818), so the ceiling here is a real-time budget, not
        // an arbitrary micro-benchmark: it must complete well under one frame at 120Hz
        // (8.3ms). A raw wall-clock `#expect` on one sample is exactly what
        // project/gotchas.md warns is unreliable in the parallel suite — a neighbor's
        // `swift build` can inflate a single measurement several-fold. `PerformanceBudget`
        // takes the minimum of several in-process repetitions instead, and is only
        // strict on an optimized build (or with $WOODCASE_BUDGET_STRICT set); a debug
        // run downgrades an overage to an advisory note unless it is far past what
        // machine load could explain.
        let budget = PerformanceBudget(
            name: "layoutSubtree of 20 flex children",
            release: .milliseconds(5)
        )
        let sample = try await PerformanceSample.measure(repetitions: budget.repetitions) {
            _ = PenLayoutEngine.layoutSubtree(
                rootID: "perf-container",
                in: doc,
                existingRects: fullRects
            )
        }
        budget.check(sample)
    }

    @Test("Node not found returns empty dictionary")
    func nodeNotFoundReturnsEmpty() {
        let doc = makeNestedDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        let subtreeRects = PenLayoutEngine.layoutSubtree(
            rootID: "nonexistent",
            in: doc,
            existingRects: fullRects
        )

        #expect(subtreeRects.isEmpty)
    }
}
