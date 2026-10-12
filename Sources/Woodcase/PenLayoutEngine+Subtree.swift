//
//  PenLayoutEngine+Subtree.swift
//  Woodcase
//

import Foundation

/// Laying out one subtree in place, at the space its parent's existing rect offers it.
public extension PenLayoutEngine {
    /// Computes layout for a single subtree, returning rects for only the target node and its descendants.
    ///
    /// Use this for interactive editing scenarios (e.g., drag-resizing a flex container) where
    /// re-laying out the entire document would be too expensive at 120Hz. The caller provides
    /// `existingRects` so the engine can derive parent constraints and preserve the subtree root's
    /// position.
    ///
    /// - Parameters:
    ///   - rootID: The ID of the subtree root to re-layout.
    ///   - document: The full document (needed for tree traversal).
    ///   - existingRects: Current layout rects (used for parent constraints and position).
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - options: The cards drawn raw (``PenLayoutOptions``). Defaults to none.
    /// - Returns: A dictionary of rects for the subtree only. Empty if `rootID` is not found.
    static func layoutSubtree(
        rootID: String,
        in document: PenDocument,
        existingRects: [String: PenRect],
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        options: PenLayoutOptions = PenLayoutOptions()
    ) -> [String: PenRect] {
        var memo = Memo()
        return layoutSubtreeImpl(
            rootID: rootID, in: document, existingRects: existingRects,
            textMeasurer: textMeasurer, options: options, memo: &memo
        )
    }

    /// Computes layout for a single subtree with a measurement cache for cross-frame persistence.
    ///
    /// Like ``layoutSubtree(rootID:in:existingRects:textMeasurer:options:)``, but uses a measurement cache
    /// to skip re-computing unchanged sub-subtrees.
    ///
    /// - Parameters:
    ///   - rootID: The ID of the subtree root to re-layout.
    ///   - document: The full document (needed for tree traversal).
    ///   - existingRects: Current layout rects (used for parent constraints and position).
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - options: The cards drawn raw (``PenLayoutOptions``). Defaults to none.
    ///   - measurementCache: A cache of per-node measurement results, mutated in place.
    /// - Returns: A dictionary of rects for the subtree only. Empty if `rootID` is not found.
    static func layoutSubtree(
        rootID: String,
        in document: PenDocument,
        existingRects: [String: PenRect],
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        options: PenLayoutOptions = PenLayoutOptions(),
        measurementCache: inout [String: MeasurementCacheEntry]
    ) -> [String: PenRect] {
        var memo = Memo(finals: measurementCache)
        let result = layoutSubtreeImpl(
            rootID: rootID, in: document, existingRects: existingRects,
            textMeasurer: textMeasurer, options: options, memo: &memo
        )
        measurementCache = memo.finals
        return result
    }
}

// MARK: - Subtree Layout

private extension PenLayoutEngine {
    /// Searches the tree for a node by ID, returning both the node and its parent — the
    /// first match in pre-order.
    static func findNodeWithParent(
        id: String,
        in nodes: [PenNode],
        parent: PenNode?
    ) -> (node: PenNode, parent: PenNode?)? {
        var pending: [(node: PenNode, parent: PenNode?)] = nodes.reversed().map { ($0, parent) }
        while let next = pending.popLast() {
            if next.node.id == id { return next }
            pending.append(contentsOf: (nodeChildren(next.node) ?? []).reversed().map { ($0, next.node) })
        }
        return nil
    }

    /// Derives the available width/height that a parent would offer to a child during layout.
    static func deriveAvailableDimensions(
        parent: PenNode?,
        existingRects: [String: PenRect]
    ) -> (width: Double?, height: Double?) {
        guard let parent, let parentRect = existingRects[parent.id] else {
            return (nil, nil) // Top-level: unconstrained, matching layout() behavior
        }
        let props = extractLayoutProperties(parent)
        let availableWidth = parentRect.width - props.padding.left - props.padding.right
        let availableHeight = parentRect.height - props.padding.top - props.padding.bottom
        return (availableWidth, availableHeight)
    }

    /// Shared implementation for both cached and uncached subtree layout.
    static func layoutSubtreeImpl(
        rootID: String,
        in document: PenDocument,
        existingRects: [String: PenRect],
        textMeasurer: TextMeasurer,
        options: PenLayoutOptions,
        memo: inout Memo
    ) -> [String: PenRect] {
        guard let (node, parent) = findNodeWithParent(
            id: rootID, in: document.children, parent: nil
        ) else {
            return [:]
        }

        let (availableWidth, availableHeight) = deriveAvailableDimensions(
            parent: parent, existingRects: existingRects
        )

        var rects: [String: PenRect] = [:]
        let size = layoutNode(
            node, availableWidth: availableWidth, availableHeight: availableHeight,
            textMeasurer: textMeasurer, options: options, into: &rects, memo: &memo
        )

        // layoutNode writes descendant rects but NOT the root's own rect. A node placed by
        // its own x/y lands where its anchor and its new size put it, as in a full layout;
        // a flow child keeps the position its parent gave it (existingRects), grown to its
        // turned bounds as the flow grows it.
        let isFree = parent.map {
            extractLayoutProperties($0).layout == .none || node.common.layoutPosition == .absolute
        } ?? true
        let declaredX = node.common.x?.literalValue ?? 0
        let declaredY = node.common.y?.literalValue ?? 0
        if isFree {
            rects[rootID] = freeRect(of: node, x: declaredX, y: declaredY, size: size, placedIn: rects)
        } else {
            let turned = applyRotationExpansion(width: size.width, height: size.height, node: node)
            let rotation = node.common.rotation?.literalValue ?? 0
            rects[rootID] = PenRect(
                x: existingRects[rootID]?.x ?? declaredX, y: existingRects[rootID]?.y ?? declaredY,
                width: turned.width, height: turned.height,
                unturnedSize: rotation == 0 ? nil : PenSize(width: size.width, height: size.height)
            )
        }

        return rects
    }
}
