//
//  PenLayoutEngine+Incremental.swift
//  Woodcase
//

import Foundation

/// Incremental layout by top-level node: a dirty root is laid out again over its previous
/// rects, through the measurement cache; every clean one keeps its rects.
extension PenLayoutEngine {
    /// Incrementally computes layout, re-laying out only roots with dirty descendants.
    ///
    /// For each top-level node, checks whether any of its descendants (or itself) are
    /// in the `dirtyNodeIDs` set. If not, the previous rects for that entire subtree
    /// are copied unchanged. If any are dirty, the entire root subtree is re-laid out.
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - previousRects: The cached layout rects from the previous pass.
    ///   - dirtyNodeIDs: Node IDs that have changed since the previous layout — a card
    ///     whose rawness changed among them.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - options: The cards drawn raw (``PenLayoutOptions``). Defaults to none.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    public static func layoutIncremental(
        _ document: PenDocument,
        previousRects: [String: PenRect],
        dirtyNodeIDs: Set<String>,
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        options: PenLayoutOptions = PenLayoutOptions()
    ) -> [String: PenRect] {
        // An empty memo answers nothing, so every dirty root is laid out whole.
        var memo = Memo()
        return layOutRoots(
            of: document, previousRects: previousRects,
            isDirty: { subtreeContainsDirty($0, dirtyNodeIDs: dirtyNodeIDs) },
            textMeasurer: textMeasurer, options: options, memo: &memo
        )
    }

    /// Incrementally computes layout with a measurement cache for cross-frame persistence.
    ///
    /// Like ``layoutIncremental(_:previousRects:dirtyNodeIDs:textMeasurer:options:)``, but uses
    /// a measurement cache to skip re-computing unchanged subtrees within dirty roots.
    /// The cache holds, per node, the offered space and size of its last *final* call —
    /// the one whose rects below the node reach the result; on a hit the subtree is
    /// skipped entirely and its rects come from `previousRects`. The caller must forget
    /// the entries of every dirty node and its ancestors — a card whose rawness changed
    /// since the cache was filled among them — and pass the rects the cache was filled
    /// alongside.
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - previousRects: The cached layout rects from the previous pass.
    ///   - dirtyNodeIDs: Node IDs that have changed since the previous layout.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - options: The cards drawn raw (``PenLayoutOptions``). Defaults to none.
    ///   - measurementCache: A cache of per-node measurement results, mutated in place.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    public static func layoutIncremental(
        _ document: PenDocument,
        previousRects: [String: PenRect],
        dirtyNodeIDs: Set<String>,
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        options: PenLayoutOptions = PenLayoutOptions(),
        measurementCache: inout [String: MeasurementCacheEntry]
    ) -> [String: PenRect] {
        var memo = Memo(finals: measurementCache)
        let rects = layOutRoots(
            of: document, previousRects: previousRects,
            isDirty: { subtreeContainsDirty($0, dirtyNodeIDs: dirtyNodeIDs) },
            textMeasurer: textMeasurer, options: options, memo: &memo
        )
        measurementCache = memo.finals
        return rects
    }

    /// Lays out the top-level nodes `isDirty` picks, through the measurement cache, and
    /// copies every other one's rects from the previous layout.
    ///
    /// A dirty root's map starts from its previous rects, so a cache hit — which skips a
    /// subtree — leaves that subtree's rects as they were.
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - previousRects: The rects of the previous layout.
    ///   - isDirty: Whether a top-level node must be laid out again.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - options: The cards drawn raw.
    ///   - memo: The sizes remembered so far, read and filled.
    /// - Returns: Every node's rect.
    static func layOutRoots(
        of document: PenDocument,
        previousRects: [String: PenRect],
        isDirty: (PenNode) -> Bool,
        textMeasurer: TextMeasurer,
        options: PenLayoutOptions,
        memo: inout Memo
    ) -> [String: PenRect] {
        var rects: [String: PenRect] = [:]
        for node in document.children {
            // Clean or dirty, the map starts from the previous rects; a dirty root is then
            // laid out over them, and cache hits keep what they skip.
            copySubtreeRects(node, from: previousRects, into: &rects)
            guard isDirty(node) else { continue }
            let x = node.common.x?.literalValue ?? 0
            let y = node.common.y?.literalValue ?? 0
            let size = layoutNode(
                node, availableWidth: nil, availableHeight: nil,
                textMeasurer: textMeasurer, options: options, into: &rects, memo: &memo
            )
            rects[node.id] = freeRect(of: node, x: x, y: y, size: size, placedIn: rects)
        }
        return rects
    }

    /// Checks whether any node in the subtree is in the dirty set, short-circuiting on the first match.
    ///
    /// This and every other walk in the engine runs from a work list, not recursion, so
    /// a deep tree cannot overflow a Swift task's stack in a debug build
    /// (`project/2026-09-26-debug-stack-depth.md`).
    private static func subtreeContainsDirty(_ node: PenNode, dirtyNodeIDs: Set<String>) -> Bool {
        var pending = [node]
        while let next = pending.popLast() {
            if dirtyNodeIDs.contains(next.id) { return true }
            pending.append(contentsOf: nodeChildren(next) ?? [])
        }
        return false
    }

    /// Copies previous rects for all nodes in a subtree into the output dict.
    ///
    /// A disabled child of a flex container is skipped with everything under it: the flow
    /// gives it no rect, so a rect it had before it was disabled must not survive. A
    /// container that places its children at their own x/y places a disabled one too.
    private static func copySubtreeRects(
        _ node: PenNode,
        from previousRects: [String: PenRect],
        into rects: inout [String: PenRect]
    ) {
        var pending = [node]
        while let next = pending.popLast() {
            if let rect = previousRects[next.id] {
                rects[next.id] = rect
            }
            guard let children = nodeChildren(next) else { continue }
            if extractLayoutProperties(next).layout == PenLayoutDirection.none {
                pending.append(contentsOf: children)
            } else {
                pending.append(contentsOf: children.filter { $0.common.enabled?.literalValue != false })
            }
        }
    }
}
