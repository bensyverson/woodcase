//
//  PenLayoutState+Hypothetical.swift
//  Woodcase
//

import Foundation

public extension PenLayoutState {
    /// Lays out the document as some edits would leave it, without changing anything.
    ///
    /// The edits land on a copy of the expanded document — the nodes they name and the
    /// parents they take a node from or move it within — and only those nodes' spines are
    /// forgotten, on a copy of the memo. The pass then walks the roots holding them: a
    /// reorder lays out the stack and its ancestors, each sibling answering from memory and
    /// only moving; a resize lays out the node, the descendants whose offered space
    /// changed, and its ancestors. The state is a value, so neither it nor any document a
    /// caller holds changes.
    ///
    /// The result equals a full layout of the document with the edits committed, so a
    /// preview hands off to the committed layout without a flash. Edits apply in order;
    /// one that names a node the state does not hold, or one an earlier edit removed, is
    /// passed over. Moving or removing a top-level node changes no rect but the removed
    /// ones: top-level nodes lay out independently.
    ///
    /// - Parameter edits: The edits to imagine, by expanded id.
    /// - Returns: What would change against ``rects``; merge it with
    ///   ``PenLayoutChange/applied(to:)``.
    func hypothetical(_ edits: [PenLayoutEdit]) -> PenLayoutChange {
        var tree = document
        var seeds: Set<String> = []
        var removed: Set<String> = []
        for edit in edits {
            let id = edit.nodeID
            guard let entry = index[id], !removed.contains(id) else { continue }
            let path = index.ancestors(of: id).reversed() + [id]
            switch edit {
            case .remove:
                removed.formUnion(index.subtree(of: id))
                guard let parent = entry.parent else {
                    tree.children.removeAll { $0.id == id }
                    continue
                }
                if Self.modify(&tree.children, along: path.dropLast()[...], { parent in
                    parent.modifyInlineChildren { $0.removeAll { $0.id == id } }
                }) {
                    seeds.insert(parent)
                }
            case let .move(_, toIndex: target):
                guard let parent = entry.parent else { continue }
                if Self.modify(&tree.children, along: path.dropLast()[...], { parent in
                    parent.modifyInlineChildren { children in
                        guard let from = children.firstIndex(where: { $0.id == id }) else { return }
                        let node = children.remove(at: from)
                        children.insert(node, at: min(max(target, 0), children.count))
                    }
                }) {
                    seeds.insert(parent)
                }
            case let .size(_, width, height):
                if Self.modify(&tree.children, along: path[...], { node in
                    node.kind.setLayoutSizing(width: width.map(PenSizing.fixed), height: height.map(PenSizing.fixed))
                }) {
                    seeds.insert(id)
                }
            case let .sizing(_, width, height):
                if Self.modify(&tree.children, along: path[...], { node in
                    node.kind.setLayoutSizing(width: width, height: height)
                }) {
                    seeds.insert(id)
                }
            }
        }

        var memo = memo
        var laidOut = rects
        for seed in seeds where !removed.contains(seed) {
            memo.forget(seed)
            for ancestor in index.ancestors(of: seed) {
                memo.forget(ancestor)
            }
        }
        for id in removed {
            laidOut.removeValue(forKey: id)
        }
        let roots = Set(seeds.subtracting(removed).compactMap { index[$0]?.root })
        memo.clearLog()
        Self.pass(over: tree, roots: roots, rects: &laidOut, memo: &memo, textMeasurer: textMeasurer, options: options)
        let dropped = Self.dropUnplaced(memo.unplaced, index: index, from: &laidOut)

        let candidates = Set(memo.written).union(removed).union(dropped)
        var change = Self.change(from: rects, to: laidOut, among: candidates, index: index, oldIndex: index)
        change.affectedRoots = roots
        change.stats = memo.stats
        return change
    }

    /// Runs `body` on the node at the end of a path of ids from the top level down.
    ///
    /// - Parameters:
    ///   - nodes: The nodes the path starts among.
    ///   - path: Ids from a top-level node down to the target.
    ///   - body: The change to make to the target.
    /// - Returns: Whether the path led to a node.
    internal static func modify(
        _ nodes: inout [PenNode], along path: ArraySlice<String>, _ body: (inout PenNode) -> Void
    ) -> Bool {
        guard let id = path.first, let position = nodes.firstIndex(where: { $0.id == id }) else { return false }
        guard path.count > 1 else {
            body(&nodes[position])
            return true
        }
        var found = false
        nodes[position].modifyInlineChildren { children in
            found = modify(&children, along: path.dropFirst(), body)
        }
        return found
    }
}
