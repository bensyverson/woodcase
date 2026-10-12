//
//  PenLayoutChange.swift
//  Woodcase
//

import Foundation

/// What a layout pass changed, against the rects it started from.
///
/// ``PenLayoutState/update(to:invalidation:)`` and ``PenLayoutState/hypothetical(_:)``
/// return one. A renderer merges ``rects`` over the rects it holds and drops ``removed``
/// (``applied(to:)``), and produces again only the subtrees under ``topmost``.
public struct PenLayoutChange: Friendly {
    /// Every node whose rect differs, with its new rect; a node that had none before is
    /// here too.
    public var rects: [String: PenRect] = [:]

    /// Nodes that had a rect and have none now.
    public var removed: Set<String> = []

    /// Changed nodes that kept their size and moved.
    public var moved: Set<String> = []

    /// Changed nodes whose size changed, or that had no rect before.
    public var resized: Set<String> = []

    /// Changed nodes with no changed ancestor — the subtrees a renderer produces again.
    public var topmost: Set<String> = []

    /// The top-level nodes the pass laid out, by expanded id.
    public var affectedRoots: Set<String> = []

    /// What the pass did.
    public var stats = PenLayoutStats()

    /// An empty change.
    public init() {}

    /// Whether nothing changed.
    public var isEmpty: Bool {
        rects.isEmpty && removed.isEmpty
    }

    /// The rects this change leaves, merged over the rects it was computed against.
    ///
    /// - Parameter base: The rects the change was computed against.
    /// - Returns: `base` with every changed rect replaced and every removed one dropped.
    public func applied(to base: [String: PenRect]) -> [String: PenRect] {
        var result = base
        for id in removed {
            result.removeValue(forKey: id)
        }
        result.merge(rects) { _, new in new }
        return result
    }
}
