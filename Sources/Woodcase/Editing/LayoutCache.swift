//
//  LayoutCache.swift
//  Woodcase
//

import Foundation

/// Holds an editing document's layout and tracks which nodes need re-layout or re-render.
///
/// The layout itself is one ``PenLayoutState`` (design decision 3 of
/// `project/2026-10-04-sub-root-layout-design.md`): the rects, the index, what the walk
/// remembers of each node's size and the bounded ``TextSizeCache``. Woodcase keeps no
/// second cache beside it; a host that runs its own pipeline holds a state of its own
/// instead of a measurement cache.
///
/// The dirty tracking is what the edits since the last ``clearDirtyNodes()`` recorded,
/// by source id. The cache distinguishes between layout-affecting changes (requiring
/// re-layout of ancestors) and render-only changes (visual update only).
///
/// Newly created caches start fully invalidated, requiring a full layout pass.
/// After the first layout pass, subsequent edits produce targeted invalidations.
///
/// The cache is owned by the ``EditableDocument`` that made it and shares that
/// document's isolation; it is not `Sendable`, exactly as ``ExpansionCache`` is not.
public final class LayoutCache {
    /// The layout, once a pass has run through the cache.
    public private(set) var state: PenLayoutState?

    /// Rects a host stored from its own pipeline (``store(rects:)``), standing until a
    /// pass runs through the cache.
    private var storedRects: [String: PenRect] = [:]

    /// The layout rectangles, keyed by expanded node id, in parent coordinates: the
    /// state's, or the rects a host stored.
    public var rects: [String: PenRect] {
        state?.rects ?? storedRects
    }

    /// Node IDs needing re-layout (size/position changed).
    public private(set) var dirtyLayoutNodes: Set<String> = []

    /// Nodes whose whole subtree needs re-layout, by source id: a `theme` change, which
    /// every descendant resolves its variables through.
    public private(set) var dirtyLayoutSubtrees: Set<String> = []

    /// The nodes inserts, moves and deletes touched, by source id: every node inserted,
    /// deleted or moved, and the parent each lands under. A host whose own pipeline
    /// cannot yet follow a change of the tree's shape node by node reads it to take its
    /// full path.
    public private(set) var structuralSubjects: Set<String> = []

    /// Node IDs needing re-render only (visual-only change).
    public private(set) var dirtyRenderNodes: Set<String> = []

    /// Whether full re-layout is needed (structural change or fresh cache).
    public private(set) var isFullyInvalidated: Bool = true

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
        dirtyLayoutNodes.formUnion(ancestors)
    }

    /// Marks a node's whole subtree as needing re-layout (a theme change, which every
    /// descendant resolves through), and its ancestors.
    ///
    /// The subtree is recorded by its root; the next pass translates it against the
    /// expanded tree.
    ///
    /// - Parameters:
    ///   - nodeID: The root of the affected subtree.
    ///   - ancestors: The ancestor chain from nearest parent to root.
    func invalidateSubtreeLayout(_ nodeID: String, ancestors: [String]) {
        invalidateLayout(nodeID, ancestors: ancestors)
        dirtyLayoutSubtrees.insert(nodeID)
    }

    /// Marks the spines of a structural edit for re-layout, and records its subjects.
    ///
    /// - Parameters:
    ///   - subjects: The nodes the edit inserted, deleted or moved, and the parent each
    ///     lands under, by source id.
    ///   - spine: The touched nodes and the placed instances drawing a touched
    ///     component, with their ancestors, by source id.
    func invalidateStructure(subjects: Set<String>, spine: Set<String>) {
        structuralSubjects.formUnion(subjects)
        dirtyLayoutNodes.formUnion(spine)
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
    }

    /// Stores rects a host computed in its own pipeline, and clears the full
    /// invalidation flag. The cache's state is dropped: the rects stand for the layout
    /// until the next pass through the cache, which lays out in full.
    ///
    /// - Parameter rects: The host's rects.
    func store(rects: [String: PenRect]) {
        state = nil
        storedRects = rects
        isFullyInvalidated = false
    }

    /// Lays out what an invalidation names through the cache's state, and clears the
    /// full invalidation flag.
    ///
    /// The first pass — or one after ``store(rects:)``, or one that must lay out
    /// everything — makes a new state with `textMeasurer`; every other pass updates the
    /// state in place, with the measurer it was made with.
    ///
    /// - Parameters:
    ///   - document: The document as edited, expanded and resolved.
    ///   - invalidation: What the edits since the last pass named, by source id.
    ///   - textMeasurer: The measurer for a new state.
    /// - Returns: What changed against ``rects`` before the pass.
    @discardableResult
    func commit(
        _ document: PenDocument, invalidation: PenLayoutInvalidation, textMeasurer: @escaping TextMeasurer
    ) -> PenLayoutChange {
        defer { isFullyInvalidated = false }
        if state != nil, !invalidation.everything, !isFullyInvalidated {
            // Updated through the optional in place, so the rects are not copied.
            return state!.update(to: document, invalidation: invalidation)
        }
        let before = rects
        let oldIndex = state?.index
        let fresh = PenLayoutState(document: document, textMeasurer: textMeasurer)
        state = fresh
        storedRects = [:]
        let candidates = Set(before.keys).union(fresh.rects.keys)
        var change = PenLayoutState.change(
            from: before, to: fresh.rects, among: candidates, index: fresh.index, oldIndex: oldIndex ?? fresh.index
        )
        change.affectedRoots = Set(fresh.index.roots)
        return change
    }

    /// Clears dirty tracking after the caller has processed updates.
    ///
    /// Call this after the editor has re-rendered the dirty nodes.
    public func clearDirtyNodes() {
        dirtyLayoutNodes.removeAll()
        dirtyLayoutSubtrees.removeAll()
        structuralSubjects.removeAll()
        dirtyRenderNodes.removeAll()
        isFullyInvalidated = false
    }
}
