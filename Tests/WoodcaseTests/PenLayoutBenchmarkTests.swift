//
//  PenLayoutBenchmarkTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Layout engine performance benchmarks for RapidPro frame budget validation.
///
/// Target: 2000 nodes < 4ms full layout, < 1ms incremental.
/// Each test warms up 1 pass, measures 10 iterations, reports median.
struct PenLayoutBenchmarkTests {
    // MARK: - No-op text measurer

    private let noopMeasurer: TextMeasurer = { _, _, _, _, _, _, _, _ in (width: 100, height: 20) }

    // MARK: - Document Generators

    /// Root frame with `layout: .none`, N rect children at absolute positions.
    private func makeAbsoluteDocument(nodeCount: Int) -> PenDocument {
        let children: [PenNode] = (0 ..< nodeCount).map { i in
            let x = Double(i % 50) * 120
            let y = Double(i / 50) * 80
            return PenNode(
                id: "abs-\(i)",
                common: PenNodeCommon(x: .literal(x), y: .literal(y)),
                kind: .rectangle(PenNode.RectangleData(
                    width: .fixed(100),
                    height: .fixed(60)
                ))
            )
        }
        return PenDocument(children: [
            PenNode(
                id: "root",
                common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(6000),
                    height: .fixed(6000),
                    layout: PenLayoutDirection.none,
                    children: children
                ))
            ),
        ])
    }

    /// Nested flex containers, total ~nodeCount leaf nodes.
    private func makeFlexDocument(nodeCount: Int, depth: Int = 3) -> PenDocument {
        func buildTree(prefix: String, remaining: Int, currentDepth: Int) -> [PenNode] {
            guard remaining > 0 else { return [] }

            if currentDepth >= depth || remaining <= 4 {
                // Leaf level: create rectangles
                return (0 ..< remaining).map { i in
                    PenNode(
                        id: "\(prefix)-leaf-\(i)",
                        common: PenNodeCommon(),
                        kind: .rectangle(PenNode.RectangleData(
                            width: .fixed(80),
                            height: .fixed(40)
                        ))
                    )
                }
            }

            // Split into child containers
            let containerCount = min(remaining, 4)
            let perContainer = remaining / containerCount
            let extraNodes = remaining % containerCount

            return (0 ..< containerCount).map { i in
                let childCount = perContainer + (i < extraNodes ? 1 : 0)
                let children = buildTree(
                    prefix: "\(prefix)-c\(i)",
                    remaining: childCount,
                    currentDepth: currentDepth + 1
                )
                let direction: PenLayoutDirection = currentDepth % 2 == 0 ? .horizontal : .vertical
                return PenNode(
                    id: "\(prefix)-c\(i)",
                    common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(
                        width: .fitContent(fallback: nil),
                        height: .fitContent(fallback: nil),
                        layout: direction,
                        gap: .literal(8),
                        children: children
                    ))
                )
            }
        }

        let children = buildTree(prefix: "flex", remaining: nodeCount, currentDepth: 0)
        return PenDocument(children: [
            PenNode(
                id: "flex-root",
                common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fitContent(fallback: nil),
                    height: .fitContent(fallback: nil),
                    layout: .vertical,
                    gap: .literal(16),
                    children: children
                ))
            ),
        ])
    }

    /// 60% absolute, 40% flex, multiple root artboards.
    private func makeMixedDocument(nodeCount: Int) -> PenDocument {
        let absoluteCount = nodeCount * 6 / 10
        let flexCount = nodeCount - absoluteCount

        let absChildren: [PenNode] = (0 ..< absoluteCount).map { i in
            PenNode(
                id: "mix-abs-\(i)",
                common: PenNodeCommon(x: .literal(Double(i % 40) * 100), y: .literal(Double(i / 40) * 60)),
                kind: .rectangle(PenNode.RectangleData(
                    width: .fixed(80),
                    height: .fixed(40)
                ))
            )
        }
        let absRoot = PenNode(
            id: "artboard-abs",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                width: .fixed(4000),
                height: .fixed(4000),
                layout: PenLayoutDirection.none,
                children: absChildren
            ))
        )

        // Build flex children inline
        let flexChildren: [PenNode] = (0 ..< flexCount).map { i in
            PenNode(
                id: "mix-flex-\(i)",
                common: PenNodeCommon(),
                kind: .rectangle(PenNode.RectangleData(
                    width: .fixed(60),
                    height: .fixed(30)
                ))
            )
        }
        // Split into rows of 10
        let rowSize = 10
        let rows: [PenNode] = stride(from: 0, to: flexChildren.count, by: rowSize).enumerated().map { idx, start in
            let end = min(start + rowSize, flexChildren.count)
            return PenNode(
                id: "mix-row-\(idx)",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    width: .fitContent(fallback: nil),
                    height: .fitContent(fallback: nil),
                    layout: .horizontal,
                    gap: .literal(4),
                    children: Array(flexChildren[start ..< end])
                ))
            )
        }
        let flexRoot = PenNode(
            id: "artboard-flex",
            common: PenNodeCommon(x: .literal(4200), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                width: .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                layout: .vertical,
                gap: .literal(8),
                children: rows
            ))
        )

        return PenDocument(children: [absRoot, flexRoot])
    }

    // MARK: - Benchmark Runner

    /// Runs a benchmark: 1 warmup pass, 10 measured iterations, returns median in seconds.
    private func benchmark(_ label: String, body: () -> Void) -> Double {
        // Warmup
        body()

        // Measure
        let clock = ContinuousClock()
        var durations: [Double] = []
        for _ in 0 ..< 10 {
            let elapsed = clock.measure { body() }
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            durations.append(seconds)
        }
        durations.sort()
        let median = durations[durations.count / 2]
        let medianMs = median * 1000
        print("[\(label)] median: \(String(format: "%.3f", medianMs))ms")
        return median
    }

    // MARK: - Full Layout: Absolute

    @Test("Absolute layout 500 nodes")
    func absoluteLayout500() {
        let doc = makeAbsoluteDocument(nodeCount: 500)
        _ = benchmark("absolute-500") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    @Test("Absolute layout 1000 nodes")
    func absoluteLayout1000() {
        let doc = makeAbsoluteDocument(nodeCount: 1000)
        _ = benchmark("absolute-1000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    @Test("Absolute layout 2000 nodes")
    func absoluteLayout2000() {
        let doc = makeAbsoluteDocument(nodeCount: 2000)
        _ = benchmark("absolute-2000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    @Test("Absolute layout 5000 nodes")
    func absoluteLayout5000() {
        let doc = makeAbsoluteDocument(nodeCount: 5000)
        _ = benchmark("absolute-5000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    @Test("Absolute layout 10000 nodes")
    func absoluteLayout10000() {
        let doc = makeAbsoluteDocument(nodeCount: 10000)
        _ = benchmark("absolute-10000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    // MARK: - Full Layout: Flex

    @Test("Flex layout 500 nodes")
    func flexLayout500() {
        let doc = makeFlexDocument(nodeCount: 500)
        _ = benchmark("flex-500") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    @Test("Flex layout 1000 nodes")
    func flexLayout1000() {
        let doc = makeFlexDocument(nodeCount: 1000)
        _ = benchmark("flex-1000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    @Test("Flex layout 2000 nodes")
    func flexLayout2000() {
        let doc = makeFlexDocument(nodeCount: 2000)
        _ = benchmark("flex-2000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    @Test("Flex layout 5000 nodes")
    func flexLayout5000() {
        let doc = makeFlexDocument(nodeCount: 5000)
        _ = benchmark("flex-5000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    // MARK: - Full Layout: Mixed

    @Test("Mixed layout 2000 nodes")
    func mixedLayout2000() {
        let doc = makeMixedDocument(nodeCount: 2000)
        _ = benchmark("mixed-2000") {
            _ = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)
        }
    }

    // MARK: - Incremental Layout

    @Test("Flex incremental layout: single dirty node in 2000-node flex doc")
    func flexIncrementalLayout2000() {
        let doc = makeFlexDocument(nodeCount: 2000)
        // Full layout first to get baseline rects
        let fullRects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        // Dirty a single leaf node deep in the tree
        let dirtyNodes: Set = ["flex-c0-c0-leaf-0"]
        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        _ = benchmark("flex-incremental-2000") {
            _ = PenLayoutEngine.layoutIncremental(
                doc,
                previousRects: fullRects,
                dirtyNodeIDs: dirtyNodes,
                textMeasurer: noopMeasurer,
                measurementCache: &measurementCache
            )
        }
    }

    @Test("Incremental layout: single dirty node in 2000-node doc")
    func incrementalLayout2000() {
        let doc = makeAbsoluteDocument(nodeCount: 2000)
        // Full layout first to get baseline rects
        let fullRects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        let dirtyNodes: Set = ["abs-500"]
        // Use a persistent measurement cache across iterations, as a real app would
        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        _ = benchmark("incremental-2000") {
            _ = PenLayoutEngine.layoutIncremental(
                doc,
                previousRects: fullRects,
                dirtyNodeIDs: dirtyNodes,
                textMeasurer: noopMeasurer,
                measurementCache: &measurementCache
            )
        }
    }
}
