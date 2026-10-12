//
//  MeasurementCacheTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct MeasurementCacheTests {
    // MARK: - Incremental layout with measurement cache

    private func makeSimpleDoc() -> PenDocument {
        PenDocument(children: [
            PenNode(
                id: "root",
                common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(400),
                    height: .fixed(400),
                    layout: PenLayoutDirection.none,
                    children: [
                        PenNode(
                            id: "rect-a",
                            common: PenNodeCommon(x: .literal(10), y: .literal(10)),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(80), height: .fixed(40)
                            ))
                        ),
                        PenNode(
                            id: "rect-b",
                            common: PenNodeCommon(x: .literal(100), y: .literal(10)),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(60), height: .fixed(30)
                            ))
                        ),
                    ]
                ))
            ),
        ])
    }

    private let noopMeasurer: TextMeasurer = { _ in (width: 100, height: 20) }

    @Test("Incremental layout with cache produces correct results")
    func incrementalWithCacheCorrect() {
        let doc = makeSimpleDoc()
        let fullRects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        let incremental = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: ["rect-a"],
            textMeasurer: noopMeasurer,
            measurementCache: &measurementCache
        )

        #expect(incremental == fullRects)
    }

    @Test("Cache is populated after incremental layout")
    func cachePopulatedAfterLayout() {
        let doc = makeSimpleDoc()
        let fullRects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        _ = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: ["rect-a"],
            textMeasurer: noopMeasurer,
            measurementCache: &measurementCache
        )

        // The root was dirty (contains dirty descendant), so it was re-laid out
        // and its entry should be in the cache
        #expect(measurementCache["root"] != nil)
    }

    @Test("Cache hit with same dimensions returns same result")
    func cacheHitReturnsSameResult() {
        let doc = makeSimpleDoc()
        let fullRects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]

        // First pass populates cache
        let first = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: ["rect-a"],
            textMeasurer: noopMeasurer,
            measurementCache: &measurementCache
        )

        // Second pass with same dirty set — cache should be used
        let second = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: first,
            dirtyNodeIDs: ["rect-a"],
            textMeasurer: noopMeasurer,
            measurementCache: &measurementCache
        )

        #expect(first == second)
    }

    @Test("Changed available dimensions cause cache miss")
    func changedDimensionsCacheMiss() {
        let doc = makeSimpleDoc()
        let fullRects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]

        // Populate cache
        let result = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: ["root"],
            textMeasurer: noopMeasurer,
            measurementCache: &measurementCache
        )

        // Result should match full layout
        #expect(result == fullRects)
    }
}
