//
//  EditableDocument+Layout.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Lays the document out, or lays out again what the edits since the last pass
    /// named, and reports what changed.
    ///
    /// The layout lives in one ``PenLayoutState`` the document's layout cache holds. The
    /// first pass — and any pass after a change no narrower rule covers (variables,
    /// themes, imports) — lays the document out in full; every later one updates the
    /// state node by node from ``layoutInvalidation``, as
    /// ``PenLayoutState/update(to:invalidation:)`` does. Either way the document is
    /// materialized, expanded and resolved, with inherited per-node theming (via
    /// `common.theme`). The rects are ``layoutRects`` afterwards.
    ///
    /// The pass does not clear the dirty tracking: call ``clearDirtyNodes()`` once the
    /// change is handled, or the next pass lays the same nodes out again.
    ///
    /// - Parameter textMeasurer: A function that measures text bounding boxes. Defaults
    ///   to ``PenLayoutEngine/defaultTextMeasurer``. A state keeps the measurer of the
    ///   pass that made it, so this one is used by a full pass only.
    /// - Returns: What changed against the rects before the pass: on the first pass,
    ///   every rect.
    @discardableResult
    func computeLayout(
        textMeasurer: @escaping TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) -> PenLayoutChange {
        let (expandedDoc, _) = expandedDocument()
        let resolvedDoc = PenVariableResolver.resolve(expandedDoc)
        return layoutCache.commit(resolvedDoc, invalidation: layoutInvalidation, textMeasurer: textMeasurer)
    }

    /// Every expanded node's rect, in its parent's coordinates, as the last layout pass
    /// left it — or as a host stored it (``primeLayoutCache(with:)``). Empty before any.
    var layoutRects: [String: PenRect] {
        _layoutCache?.rects ?? [:]
    }

    /// All nodes needing visual update since last ``clearDirtyNodes()``.
    ///
    /// This is the union of ``dirtyLayoutNodeIDs`` and ``dirtyRenderNodeIDs``.
    /// When the cache is fully invalidated (structural change), returns all cached node IDs.
    var dirtyNodeIDs: Set<String> {
        _layoutCache?.allDirtyNodes ?? []
    }

    /// Nodes needing re-layout (size/position changed).
    ///
    /// A subset of ``dirtyNodeIDs``. Includes the changed node and all its ancestors.
    var dirtyLayoutNodeIDs: Set<String> {
        _layoutCache?.dirtyLayoutNodes ?? []
    }

    /// What the edits since the last ``clearDirtyNodes()`` require laying out again, by
    /// source id.
    ///
    /// A host that runs its own pipeline takes it with the rest of the dirty tracking and
    /// hands it to
    /// ``PenLayoutEngine/layoutIncremental(_:previousRects:invalidation:textMeasurer:options:measurementCache:)``,
    /// which translates it to the expanded tree. Everything is named when the layout
    /// cache was never primed or needs a full pass.
    var layoutInvalidation: PenLayoutInvalidation {
        guard let cache = _layoutCache else { return PenLayoutInvalidation(everything: true) }
        return PenLayoutInvalidation(
            everything: cache.isFullyInvalidated,
            nodes: cache.dirtyLayoutNodes,
            subtrees: cache.dirtyLayoutSubtrees
        )
    }

    /// The nodes inserts, moves and deletes since the last ``clearDirtyNodes()``
    /// touched, by source id: every node inserted, deleted or moved, and the parent each
    /// lands under. Empty when no structural edit landed — and while
    /// ``isLayoutFullyInvalidated``, which a host already treats as a full pass.
    var structurallyEditedNodeIDs: Set<String> {
        _layoutCache?.structuralSubjects ?? []
    }

    /// Nodes needing re-render only (visual-only change like color/opacity).
    ///
    /// A subset of ``dirtyNodeIDs``. These nodes have unchanged layout rects.
    var dirtyRenderNodeIDs: Set<String> {
        _layoutCache?.dirtyRenderNodes ?? []
    }

    /// Clears dirty tracking after the caller has processed updates.
    ///
    /// Call this after the editor has re-rendered the dirty nodes.
    func clearDirtyNodes() {
        _layoutCache?.clearDirtyNodes()
    }

    // MARK: - External Pipeline API

    /// Whether the layout cache requires a full re-layout.
    ///
    /// Returns `true` when no cache exists (never primed) or after a change the cache
    /// cannot scope (variable, theme or import change, replace, detach). An insert,
    /// move or delete marks only the spines it touches, and those of the instances
    /// drawing a component it touched (``dirtyLayoutNodeIDs``); it is listed in
    /// ``structurallyEditedNodeIDs``.
    /// The pipeline uses this to decide between the incremental and full paths.
    var isLayoutFullyInvalidated: Bool {
        _layoutCache?.isFullyInvalidated ?? true
    }

    /// Initializes or replaces the layout cache with externally computed rects.
    ///
    /// Call this after a full pipeline run so that subsequent edits produce
    /// targeted dirty tracking instead of full invalidation. The cache's
    /// ``PenLayoutState`` is dropped, so the next ``computeLayout(textMeasurer:)`` or
    /// ``layoutIncremental(document:textMeasurer:)`` lays out in full.
    ///
    /// - Parameter rects: The layout rects computed by a full `PenLayoutEngine.layout()` call.
    func primeLayoutCache(with rects: [String: PenRect]) {
        layoutCache.store(rects: rects)
    }

    /// Lays out what the edits since the last pass named, on a document the host
    /// expanded and resolved itself.
    ///
    /// Designed for hosts that run their own pipeline (expansion, resolution,
    /// font preparation) and need to call layout separately. It is
    /// ``computeLayout(textMeasurer:)`` without the expansion: the same state, updated
    /// node by node from ``layoutInvalidation``, or laid out in full when there is none
    /// yet or a full pass is needed.
    ///
    /// - Parameters:
    ///   - document: A fully resolved `PenDocument` (refs expanded, variables resolved).
    ///   - textMeasurer: A function that measures text bounding boxes, for a full pass.
    ///     Defaults to ``PenLayoutEngine/defaultTextMeasurer``.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    func layoutIncremental(
        document: PenDocument,
        textMeasurer: @escaping TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) -> [String: PenRect] {
        layoutCache.commit(document, invalidation: layoutInvalidation, textMeasurer: textMeasurer)
        return layoutRects
    }

    // MARK: - Content Hash

    /// Computes a content hash for a node, incorporating its properties, layout rect,
    /// and recursively its children's hashes.
    ///
    /// The editor app can store this alongside rendered tiles — if the hash is unchanged,
    /// the tile is still valid. Returns `nil` if the node doesn't exist.
    ///
    /// - Parameter nodeID: The node to hash.
    /// - Returns: A combined hash value, or `nil` if the node doesn't exist.
    func contentHash(for nodeID: String) -> Int? {
        guard let node = nodes[nodeID] else { return nil }
        var hasher = Hasher()
        hasher.combine(node)
        if let rect = layoutRects[nodeID] {
            hasher.combine(rect)
        }
        for childID in children[nodeID] ?? [] {
            if let childHash = contentHash(for: childID) {
                hasher.combine(childHash)
            }
        }
        return hasher.finalize()
    }
}

extension EditableDocument {
    /// The document's layout cache, made on first use.
    var layoutCache: LayoutCache {
        if let cache = _layoutCache { return cache }
        let cache = LayoutCache()
        _layoutCache = cache
        return cache
    }
}
