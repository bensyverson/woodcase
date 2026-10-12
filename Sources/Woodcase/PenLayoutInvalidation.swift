//
//  PenLayoutInvalidation.swift
//  Woodcase
//

import Foundation

/// What the edits since the last layout require laying out again, by **source** id.
///
/// An ``EditableDocument`` records it as it is edited
/// (``EditableDocument/layoutInvalidation``), in the ids the document stores. Layout runs
/// on the *expanded* document, where an instance's nodes answer to `<ref>/<id>`, so a
/// host translates it against the expanded tree with
/// ``PenLayoutIndex/expandedIDs(for:)`` — or hands it straight to
/// ``PenLayoutEngine/layoutIncremental(_:previousRects:invalidation:textMeasurer:options:measurementCache:)``,
/// which does.
///
/// The record is a value with no reference to the document, so a host can take it on the
/// document's actor and lay out from it anywhere.
public struct PenLayoutInvalidation: Friendly {
    /// Whether every node must be laid out afresh: a variable, theme axis, import or
    /// read-context change, or a structural change no narrower rule covers.
    public var everything: Bool

    /// Nodes whose own layout inputs changed, and every ancestor of each.
    ///
    /// A node keeps its id after expansion, except a `ref`: it names its instance, whose
    /// every node is laid out afresh.
    public var nodes: Set<String>

    /// Nodes whose whole subtree must be laid out afresh — a node whose `theme` changed,
    /// which every descendant resolves its variables through.
    public var subtrees: Set<String>

    /// Top-level nodes to lay out whole, by source id: a host's own coarse invalidation.
    ///
    /// An ``EditableDocument`` names none. An edit that expansion carries into other
    /// boards — anything inside a component, structural or not, or a change to whether a
    /// node *is* one — names the refs of the placed instances that draw it in ``nodes``,
    /// each laid out whole with its ancestors, rather than the boards holding them.
    public var roots: Set<String>

    /// An invalidation.
    ///
    /// - Parameters:
    ///   - everything: Whether every node must be laid out afresh.
    ///   - nodes: Nodes whose own layout inputs changed, with their ancestors.
    ///   - subtrees: Nodes whose whole subtree must be laid out afresh.
    ///   - roots: Top-level nodes to lay out whole.
    public init(
        everything: Bool = false,
        nodes: Set<String> = [],
        subtrees: Set<String> = [],
        roots: Set<String> = []
    ) {
        self.everything = everything
        self.nodes = nodes
        self.subtrees = subtrees
        self.roots = roots
    }

    /// Whether nothing needs laying out again.
    public var isEmpty: Bool {
        !everything && nodes.isEmpty && subtrees.isEmpty && roots.isEmpty
    }

    /// Both invalidations together, field by field.
    ///
    /// - Parameter other: The invalidation to add — say, a rawness change
    ///   (``PenLayoutOptions/invalidation(from:)``) to what the document recorded.
    /// - Returns: An invalidation naming everything either names.
    public func union(_ other: PenLayoutInvalidation) -> PenLayoutInvalidation {
        var merged = self
        merged.formUnion(other)
        return merged
    }

    /// Adds another invalidation, field by field: ``everything`` when either says so,
    /// and the union of ``nodes``, ``subtrees`` and ``roots``.
    ///
    /// A host merges the invalidations of the layout runs a newer one superseded, so the
    /// run that delivers lays out everything they named.
    ///
    /// - Parameter other: The invalidation to add.
    public mutating func formUnion(_ other: PenLayoutInvalidation) {
        everything = everything || other.everything
        nodes.formUnion(other.nodes)
        subtrees.formUnion(other.subtrees)
        roots.formUnion(other.roots)
    }
}
