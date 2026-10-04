//
//  ChangeInvalidation.swift
//  Woodcase
//

import Foundation

/// What a change can have changed, for the caches and views that must catch up.
///
/// ``nodes`` names every node whose own content, children or place the change touched
/// — including the parent a node was moved or deleted *out of*, which only the
/// document before the change knows. It does not name the instances that draw an
/// edited component, nor the ancestors of what changed: a consumer that caches by
/// subtree walks up from these, and one that caches expansions re-expands when any
/// of them is a component or inside one.
///
/// ```swift
/// let change = try session.submit(.local(edit))
/// if change.invalidation.full { pipeline.rebuildAll() }
/// else { pipeline.refresh(change.invalidation.nodes, category: change.invalidation.category) }
/// ```
public struct ChangeInvalidation: Friendly {
    /// Creates an invalidation.
    ///
    /// - Parameters:
    ///   - nodes: The nodes the change touched.
    ///   - category: How much layout the change can have moved.
    ///   - documentLevel: The document-level members the change touched.
    ///   - structural: Whether the tree's shape changed.
    ///   - full: Whether every node may now render differently.
    public init(
        nodes: Set<String> = [],
        category: ChangeCategory? = nil,
        documentLevel: Set<DocumentChangeKey> = [],
        structural: Bool = false,
        full: Bool = false
    ) {
        self.nodes = nodes
        self.category = category
        self.documentLevel = documentLevel
        self.structural = structural
        self.full = full
    }

    /// The nodes the change touched: written, inserted, removed, moved, or the parent a
    /// node arrived under or left. A removed node is named so its caches can be dropped.
    public var nodes: Set<String>

    /// The most severe layout effect of the change, or `nil` when nothing a layout
    /// reads changed.
    public var category: ChangeCategory?

    /// The document-level members the change touched: variables, imports, theme axes,
    /// fonts, the root's other keys, and ``DocumentChangeKey/rootOrder`` when a
    /// top-level node arrived, left or moved.
    public var documentLevel: Set<DocumentChangeKey>

    /// Whether the tree's shape changed: a node inserted, deleted, moved, replaced or
    /// detached.
    public var structural: Bool

    /// Whether every node may now render differently: a variable, import, theme axis or
    /// font declaration changed, which any node can read.
    public var full: Bool

    /// Whether the change touched nothing at all.
    public var isEmpty: Bool {
        self == ChangeInvalidation()
    }

    /// Merges another invalidation into this one, keeping the more severe of each.
    ///
    /// - Parameter other: The invalidation to merge in.
    public mutating func formUnion(_ other: ChangeInvalidation) {
        nodes.formUnion(other.nodes)
        category = ChangeCategory.merge(category, other.category)
        documentLevel.formUnion(other.documentLevel)
        structural = structural || other.structural
        full = full || other.full
    }
}
