//
//  EditableDocument+Layout.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Computes or incrementally updates layout rectangles.
    ///
    /// On the first call, performs a full layout pass (materialize → expand → resolve → layout).
    /// Subsequent calls re-layout only root subtrees that contain dirty nodes.
    /// Variables are resolved with inherited per-node theming (via `common.theme`).
    ///
    /// - Parameter textMeasurer: A function that measures text bounding boxes.
    ///   Defaults to ``PenLayoutEngine/defaultTextMeasurer``.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    @discardableResult
    func computeLayout(
        textMeasurer: TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) -> [String: PenRect] {
        // Ensure the layout cache exists
        if _layoutCache == nil {
            _layoutCache = LayoutCache()
        }
        let cache = _layoutCache!

        // Expand refs and resolve variables
        let (expandedDoc, _) = expandedDocument()
        let resolvedDoc = PenVariableResolver.resolve(expandedDoc)

        let rects: [String: PenRect] = if cache.isFullyInvalidated || cache.rects.isEmpty {
            // Full layout pass
            PenLayoutEngine.layout(resolvedDoc, textMeasurer: textMeasurer)
        } else {
            // Incremental layout — only re-layout dirty root subtrees
            PenLayoutEngine.layoutIncremental(
                resolvedDoc,
                previousRects: cache.rects,
                dirtyNodeIDs: cache.dirtyLayoutNodes,
                textMeasurer: textMeasurer,
                measurementCache: &cache.measurementCache
            )
        }

        cache.store(rects: rects)
        return rects
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
    /// Returns `true` when no cache exists (never primed) or after a structural
    /// edit (insert, delete, move, variable/theme/import change).
    /// The pipeline uses this to decide between the incremental and full paths.
    var isLayoutFullyInvalidated: Bool {
        _layoutCache?.isFullyInvalidated ?? true
    }

    /// Initializes or replaces the layout cache with externally computed rects.
    ///
    /// Call this after a full pipeline run so that subsequent edits produce
    /// targeted dirty tracking instead of full invalidation.
    ///
    /// - Parameter rects: The layout rects computed by a full `PenLayoutEngine.layout()` call.
    func primeLayoutCache(with rects: [String: PenRect]) {
        if _layoutCache == nil {
            _layoutCache = LayoutCache()
        }
        _layoutCache!.store(rects: rects)
    }

    /// Performs incremental layout using the cache's dirty state and previous rects.
    ///
    /// Designed for hosts that run their own pipeline (expansion, resolution,
    /// font preparation) and need to call layout separately. Uses the layout
    /// cache's dirty nodes and measurement cache for efficient re-layout.
    ///
    /// Falls back to a full layout if the cache has no previous rects.
    /// Stores the result in the cache automatically.
    ///
    /// - Parameters:
    ///   - document: A fully resolved `PenDocument` (refs expanded, variables resolved).
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///     Defaults to ``PenLayoutEngine/defaultTextMeasurer``.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    func layoutIncremental(
        document: PenDocument,
        textMeasurer: TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) -> [String: PenRect] {
        if _layoutCache == nil {
            _layoutCache = LayoutCache()
        }
        let cache = _layoutCache!

        let rects: [String: PenRect] = if cache.rects.isEmpty {
            PenLayoutEngine.layout(document, textMeasurer: textMeasurer)
        } else {
            PenLayoutEngine.layoutIncremental(
                document,
                previousRects: cache.rects,
                dirtyNodeIDs: cache.dirtyLayoutNodes,
                textMeasurer: textMeasurer,
                measurementCache: &cache.measurementCache
            )
        }

        cache.store(rects: rects)
        return rects
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
        if let rect = _layoutCache?.rects[nodeID] {
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
