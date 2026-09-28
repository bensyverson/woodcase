//
//  LayoutCacheTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct LayoutCacheTests {
    @Test("Newly created cache is fully invalidated")
    func newCacheIsFullyInvalidated() {
        let cache = LayoutCache()
        #expect(cache.isFullyInvalidated == true)
        #expect(cache.dirtyLayoutNodes.isEmpty)
        #expect(cache.dirtyRenderNodes.isEmpty)
    }

    @Test("Store rects makes them accessible")
    func storeRectsAccessible() {
        let cache = LayoutCache()
        let rects: [String: PenRect] = [
            "node1": PenRect(x: 0, y: 0, width: 100, height: 50),
            "node2": PenRect(x: 100, y: 0, width: 200, height: 100),
        ]
        cache.store(rects: rects)
        #expect(cache.rects["node1"] == PenRect(x: 0, y: 0, width: 100, height: 50))
        #expect(cache.rects["node2"] == PenRect(x: 100, y: 0, width: 200, height: 100))
        // Storing clears full invalidation
        #expect(cache.isFullyInvalidated == false)
    }

    @Test("InvalidateLayout adds node and ancestors to dirty set")
    func invalidateLayoutAddsAncestors() {
        let cache = LayoutCache()
        cache.store(rects: [:])
        cache.invalidateLayout("child1", ancestors: ["parent1", "root1"])
        #expect(cache.dirtyLayoutNodes.contains("child1"))
        #expect(cache.dirtyLayoutNodes.contains("parent1"))
        #expect(cache.dirtyLayoutNodes.contains("root1"))
        #expect(cache.dirtyLayoutNodes.count == 3)
    }

    @Test("InvalidateRender adds only the node")
    func invalidateRenderAddsOnlyNode() {
        let cache = LayoutCache()
        cache.store(rects: [:])
        cache.invalidateRender("node1")
        #expect(cache.dirtyRenderNodes.contains("node1"))
        #expect(cache.dirtyLayoutNodes.isEmpty)
    }

    @Test("InvalidateAll sets fully invalidated flag")
    func invalidateAllSetsFlag() {
        let cache = LayoutCache()
        cache.store(rects: [:])
        #expect(cache.isFullyInvalidated == false)
        cache.invalidateAll()
        #expect(cache.isFullyInvalidated == true)
    }

    @Test("ClearDirtyNodes empties dirty sets and resets full invalidation")
    func clearDirtyNodesEmptiesSets() {
        let cache = LayoutCache()
        cache.store(rects: [:])
        cache.invalidateLayout("node1", ancestors: ["root1"])
        cache.invalidateRender("node2")
        #expect(!cache.dirtyLayoutNodes.isEmpty)
        #expect(!cache.dirtyRenderNodes.isEmpty)

        cache.clearDirtyNodes()
        #expect(cache.dirtyLayoutNodes.isEmpty)
        #expect(cache.dirtyRenderNodes.isEmpty)
        #expect(cache.isFullyInvalidated == false)
    }

    @Test("allDirtyNodes is union of layout and render sets")
    func allDirtyNodesIsUnion() {
        let cache = LayoutCache()
        cache.store(rects: [:])
        cache.invalidateLayout("node1", ancestors: [])
        cache.invalidateRender("node2")
        let all = cache.allDirtyNodes
        #expect(all.contains("node1"))
        #expect(all.contains("node2"))
        #expect(all.count == 2)
    }

    @Test("Multiple invalidations accumulate")
    func multipleInvalidationsAccumulate() {
        let cache = LayoutCache()
        cache.store(rects: [:])
        cache.invalidateLayout("child1", ancestors: ["root1"])
        cache.invalidateRender("child2")
        cache.invalidateLayout("child3", ancestors: ["root1"])
        // root1 appears from two different invalidations but should be counted once
        #expect(cache.dirtyLayoutNodes == Set(["child1", "child3", "root1"]))
        #expect(cache.dirtyRenderNodes == Set(["child2"]))
    }

    @Test("InvalidateSubtreeLayout marks node and ancestors")
    func invalidateSubtreeLayout() {
        let cache = LayoutCache()
        cache.store(rects: [:])
        cache.invalidateSubtreeLayout("node1", ancestors: ["parent1", "root1"])
        #expect(cache.dirtyLayoutNodes.contains("node1"))
        #expect(cache.dirtyLayoutNodes.contains("parent1"))
        #expect(cache.dirtyLayoutNodes.contains("root1"))
    }
}
