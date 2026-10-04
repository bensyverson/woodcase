//
//  ChangeWalk.swift
//  Woodcase
//

import Foundation

/// The pruned walk behind ``DocumentChanges/init(from:to:)``.
///
/// Top-down from the roots of both documents, by a work list rather than recursion so
/// a deep tree cannot overflow the stack. A node both documents hold with one
/// ``EditableDocument/revision(of:)`` pins an identical subtree, so the walk records
/// only that node's own placement and goes no deeper; any other node held by both is
/// compared and walked into through the union of its two child lists. A node only one
/// document holds is walked fully on that side, because a new container can adopt
/// nodes the other side holds elsewhere, and each of those is then compared in turn.
///
/// A revision hashes a declared `"children": []` apart from absent children, so that
/// difference moves every ancestor's revision too and the walk reaches it like any other.
struct ChangeWalk {
    /// The source document.
    let from: EditableDocument

    /// The target document.
    let to: EditableDocument

    /// How many node ids the walk has examined, for tests of its pruning.
    private(set) var visits = 0

    /// Creates a walk over two documents.
    ///
    /// - Parameters:
    ///   - from: The source document.
    ///   - to: The target document.
    init(from: EditableDocument, to: EditableDocument) {
        self.from = from
        self.to = to
    }

    /// Walks both documents and returns what differs.
    ///
    /// - Returns: The change set from ``from`` to ``to``.
    mutating func run() -> DocumentChanges {
        var changes = DocumentChanges(document: DocumentChangeKey.differences(from: from, to: to))
        var visited: Set<String> = []
        var pending: [String] = Self.union(from.rootOrder, to.rootOrder).reversed()

        while let id = pending.popLast() {
            guard visited.insert(id).inserted else { continue }
            visits += 1
            let before = Self.state(of: id, in: from)
            let after = Self.state(of: id, in: to)

            guard let before, let after else {
                guard let only = before ?? after else { continue }
                changes.nodes[id] = NodeChange(from: before, to: after)
                pending.append(contentsOf: (only.children ?? []).reversed())
                continue
            }

            let pruned = from.revision(of: id) == to.revision(of: id)
            var keys = Self.placementKeys(before, after)
            if !pruned {
                keys.formUnion(NodeChangeKey.contentDifferences(before.node, after.node))
                pending.append(contentsOf: Self.union(before.children ?? [], after.children ?? []).reversed())
            }
            if !keys.isEmpty {
                changes.nodes[id] = NodeChange(from: before, to: after, keys: keys)
            }
        }

        return changes
    }

    /// The keys of a node's place in the tree that differ: its parent, its child list
    /// and whether it declares one.
    private static func placementKeys(_ before: NodeChange.State, _ after: NodeChange.State) -> Set<NodeChangeKey> {
        var keys: Set<NodeChangeKey> = []
        if before.parentID != after.parentID { keys.insert(.parent) }
        if (before.children ?? []) != (after.children ?? []) { keys.insert(.children) }
        if (before.children == nil) != (after.children == nil) { keys.insert(.declaredChildren) }
        return keys
    }

    /// A node as `document` holds it, or `nil` if it holds none.
    private static func state(of id: String, in document: EditableDocument) -> NodeChange.State? {
        guard let node = document.nodes[id] else { return nil }
        return NodeChange.State(node: node, parentID: document.parents[id], children: document.children[id])
    }

    /// The ids of `first`, then those of `second` that `first` lacks, each in order.
    private static func union(_ first: [String], _ second: [String]) -> [String] {
        let seen = Set(first)
        return first + second.filter { !seen.contains($0) }
    }
}
