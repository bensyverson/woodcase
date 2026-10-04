//
//  OpSequencer+Structure.swift
//  Woodcase
//

import Foundation

/// Phase 3: every child list the merge changes, made left to right.
extension OpSequencer {
    /// Makes every changed child list, parents before their children.
    ///
    /// A list's own container is in its final place before the list is made — its
    /// ancestors' lists are made first, and an unchanged list never loses a member —
    /// so a node moved into it is never one of its ancestors.
    mutating func buildStructure() {
        if resolution.rootOrder != nil {
            makeList(of: nil)
        }
        var depths: [String: Int] = [:]
        let containers = resolution.nodes.keys.filter(listChanges)
        let ordered = containers.map { (id: $0, depth: depth(of: $0, memo: &depths)) }
            .sorted { ($0.depth, $0.id) < ($1.depth, $1.id) }
        for (id, _) in ordered {
            makeList(of: id)
        }
    }

    /// Whether a node's merged child list is one the structural pass must make.
    private func listChanges(_ id: String) -> Bool {
        let wanted = finalChildren(of: id)
        guard !isNew(id) else { return wanted.contains { !isNew($0) } }
        return wanted != (ours.children[id] ?? [])
    }

    /// A node's depth in the merged tree; top-level nodes are 0.
    private func depth(of id: String, memo: inout [String: Int]) -> Int {
        var chain: [String] = []
        var cursor: String? = id
        var base = -1
        while let node = cursor {
            if let known = memo[node] {
                base = known
                break
            }
            chain.append(node)
            cursor = finalState(of: node)?.parentID
        }
        for (offset, node) in chain.reversed().enumerated() {
            memo[node] = base + 1 + offset
        }
        return memo[id] ?? 0
    }

    /// Makes one list — a container's, or the top level's for `nil` — match the merged
    /// one from the left, inserting what is new and moving what sits elsewhere.
    private mutating func makeList(of parent: String?) {
        for (index, id) in finalChildren(of: parent).enumerated() {
            let now = parent.map { list(of: $0) ?? [] } ?? (topLevel ?? ours.rootOrder)
            if index < now.count, now[index] == id { continue }
            if isNew(id), placedParent[id] == nil {
                let subtree = buildSubtree(id)
                operations.append(.insertNode(EditOperation.InsertNode(node: subtree, parentID: parent, index: index)))
                attach(id, to: parent, at: index)
            } else {
                operations.append(.moveNode(EditOperation.MoveNode(nodeID: id, newParentID: parent, index: index)))
                detach(id)
                attach(id, to: parent, at: index)
            }
        }
    }

    /// A new node with every new node under it inline, in merged order. A child the
    /// local document already holds is left out, for its own list to move it in; the
    /// inline nodes are recorded as placed.
    private mutating func buildSubtree(_ id: String) -> PenNode {
        guard let state = finalState(of: id) else {
            preconditionFailure("Node \(id) is in a merged list but has no merged state")
        }
        var node = state.node
        let inline = state.children?.filter(isNew)
        let built = inline?.map { child -> PenNode in
            placedParent[child] = .some(id)
            return buildSubtree(child)
        }
        node.kind = node.kind.withChildren(built)
        lists[id] = .some(inline)
        return node
    }
}
