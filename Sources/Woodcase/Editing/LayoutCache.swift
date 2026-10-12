//
//  LayoutCache.swift
//  Woodcase
//

import Foundation

/// Caches layout rectangles and tracks which nodes need re-layout or re-render.
///
/// The layout cache enables incremental updates: after an edit, only the dirty
/// subtrees are re-laid out. The cache distinguishes between layout-affecting changes
/// (requiring re-layout of ancestors) and render-only changes (visual update only).
///
/// Newly created caches start fully invalidated, requiring a full layout pass.
/// After the first layout pass stores its rects, subsequent edits produce targeted invalidations.
///
/// The cache is owned by the ``EditableDocument`` that made it and shares that
/// document's isolation; it is not `Sendable`, exactly as ``ExpansionCache`` is not.
public final class LayoutCache {
    /// Cached layout rectangles, keyed by node ID.
    public internal(set) var rects: [String: PenRect] = [:]

    /// Node IDs needing re-layout (size/position changed).
    public private(set) var dirtyLayoutNodes: Set<String> = []

    /// Top-level nodes to lay out afresh, by source id: the boards a structural edit
    /// can change, and the roots whose revision an edit inside a component moved.
    public private(set) var dirtyLayoutRoots: Set<String> = []

    /// Nodes whose whole subtree needs re-layout, by source id: a `theme` change, which
    /// every descendant resolves its variables through.
    public private(set) var dirtyLayoutSubtrees: Set<String> = []

    /// Node IDs needing re-render only (visual-only change).
    public private(set) var dirtyRenderNodes: Set<String> = []

    /// Whether full re-layout is needed (structural change or fresh cache).
    public private(set) var isFullyInvalidated: Bool = true

    /// Cached measurement results for incremental layout. Keyed by node ID.
    ///
    /// Stores the last computed size for each node given specific available dimensions.
    /// Evicted when the node or an ancestor is invalidated.
    public var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]

    public init() {}

    /// All dirty nodes (union of layout and render sets).
    ///
    /// When ``isFullyInvalidated`` is true, this returns all cached node IDs
    /// since every node needs updating.
    public var allDirtyNodes: Set<String> {
        if isFullyInvalidated {
            return Set(rects.keys)
        }
        return dirtyLayoutNodes.union(dirtyRenderNodes)
    }

    /// Marks a node and its ancestors as needing re-layout.
    ///
    /// - Parameters:
    ///   - nodeID: The node that changed.
    ///   - ancestors: The ancestor chain from nearest parent to root.
    func invalidateLayout(_ nodeID: String, ancestors: [String]) {
        dirtyLayoutNodes.insert(nodeID)
        measurementCache.removeValue(forKey: nodeID)
        for ancestor in ancestors {
            dirtyLayoutNodes.insert(ancestor)
            measurementCache.removeValue(forKey: ancestor)
        }
    }

    /// Marks a node's whole subtree as needing re-layout (a theme change, which every
    /// descendant resolves through), and its ancestors.
    ///
    /// The subtree is recorded by its root; its nodes' measurements are forgotten when
    /// the next layout translates it against the expanded tree.
    ///
    /// - Parameters:
    ///   - nodeID: The root of the affected subtree.
    ///   - ancestors: The ancestor chain from nearest parent to root.
    func invalidateSubtreeLayout(_ nodeID: String, ancestors: [String]) {
        invalidateLayout(nodeID, ancestors: ancestors)
        dirtyLayoutSubtrees.insert(nodeID)
    }

    /// Marks top-level nodes for a whole fresh pass.
    ///
    /// - Parameter roots: The top-level nodes, by source id.
    func invalidateRoots(_ roots: Set<String>) {
        dirtyLayoutNodes.formUnion(roots)
        dirtyLayoutRoots.formUnion(roots)
    }

    /// Marks the spine of a structural edit for re-layout, and the top-level nodes it
    /// can change for a whole fresh pass.
    ///
    /// The root ids join ``dirtyLayoutNodes`` too, so a host that lays out from that
    /// set alone still re-lays every affected root.
    ///
    /// - Parameters:
    ///   - spine: The touched nodes and their ancestors, by source id.
    ///   - roots: The top-level nodes to lay out whole, by source id.
    func invalidateStructure(spine: Set<String>, roots: Set<String>) {
        dirtyLayoutNodes.formUnion(spine)
        dirtyLayoutNodes.formUnion(roots)
        dirtyLayoutRoots.formUnion(roots)
        for id in spine {
            measurementCache.removeValue(forKey: id)
        }
    }

    /// Marks a node as needing re-render only (no layout change).
    ///
    /// - Parameter nodeID: The node with a visual-only change.
    func invalidateRender(_ nodeID: String) {
        dirtyRenderNodes.insert(nodeID)
    }

    /// Marks the entire cache as needing full re-layout.
    ///
    /// Used for document-level changes (variables, themes, imports) and the
    /// structural changes that are not yet scoped (replace, detach, remote edits).
    func invalidateAll() {
        isFullyInvalidated = true
        measurementCache.removeAll()
    }

    /// Stores computed layout rects and clears the full invalidation flag.
    ///
    /// Called after a layout pass completes.
    func store(rects: [String: PenRect]) {
        self.rects = rects
        isFullyInvalidated = false
    }

    /// Clears dirty tracking after the caller has processed updates.
    ///
    /// Call this after the editor has re-rendered the dirty nodes.
    public func clearDirtyNodes() {
        dirtyLayoutNodes.removeAll()
        dirtyLayoutRoots.removeAll()
        dirtyLayoutSubtrees.removeAll()
        dirtyRenderNodes.removeAll()
        isFullyInvalidated = false
    }
}
