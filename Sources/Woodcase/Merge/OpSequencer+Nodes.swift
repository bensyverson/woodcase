//
//  OpSequencer+Nodes.swift
//  Woodcase
//

import Foundation

/// The per-node phases: retypes, content, deletes and declared children.
extension OpSequencer {
    /// The kept nodes the merge changes, in a stable order.
    private var keptChanges: [(id: String, state: NodeChange.State)] {
        resolution.nodes.filter { !isNew($0.key) }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Whether the merge changes a kept node's type.
    private func isRetyped(_ id: String, to state: NodeChange.State) -> Bool {
        ours.nodes[id].map { $0.kind.typeName != state.node.kind.typeName } ?? false
    }

    // MARK: - Phase 2

    /// Retypes every kept node that becomes a container, before anything moves into it.
    mutating func retypeToContainers() {
        for (id, state) in keptChanges where isRetyped(id, to: state) && state.node.kind.canHaveChildren {
            retype(id, to: state.node)
        }
    }

    // MARK: - Phase 4

    /// Writes every kept node's merged content phase 6 does not, as one
    /// `setProperties` per node.
    mutating func writeContents() {
        for (id, state) in keptChanges where !(isRetyped(id, to: state) && !state.node.kind.canHaveChildren) {
            writeContent(of: id, to: state.node)
        }
    }

    /// Patches a node from its content now to `merged`, path by path.
    private mutating func writeContent(of id: String, to merged: PenNode) {
        guard let now = contentNow(of: id), now != merged else { return }
        var properties: [String: AnyCodable] = [:]
        for key in NodeChangeKey.contentDifferences(now, merged) {
            guard let path = key.propertyPath, key != .type else { continue }
            properties[path] = ThreeWayResolver.value(at: path, of: merged)
        }
        assert(
            (try? properties.reduce(now) { try NodePropertyCodec.setting($1.value, at: $1.key, on: $0) }) == merged,
            "Node \(id): patching its content through the codec does not reach the merged node — the vocabulary has drifted"
        )
        guard !properties.isEmpty else { return }
        operations.append(.setProperties(EditOperation.SetProperties(nodeID: id, properties: properties)))
        current[id] = merged
    }

    // MARK: - Phase 5

    /// Deletes every topmost node the merge removes. Subtrees holding no component go
    /// first, then each one whose components no remaining subtree still uses; a set
    /// that use each other's components is deleted detaching what it strands, which the
    /// next delete then removes.
    mutating func deleteRemoved() {
        var pending = resolution.removed.filter { id in ours.parents[id].map { !resolution.removed.contains($0) } ?? true }
            .sorted()
        var subtrees: [String: (components: Set<String>, refs: Set<String>)] = [:]
        for id in pending {
            var components: Set<String> = []
            var refs: Set<String> = []
            for node in ours.descendantIDs(of: id) {
                if ours.componentRegistry[node] != nil { components.insert(node) }
                if case let .ref(data)? = ours.nodes[node]?.kind { refs.insert(data.ref) }
            }
            subtrees[id] = (components, refs.subtracting(components))
        }
        while !pending.isEmpty {
            let index = pending.firstIndex { id in
                let components = subtrees[id]?.components ?? []
                return pending.allSatisfy { other in other == id || subtrees[other]?.refs.isDisjoint(with: components) ?? true }
            }
            let id = pending.remove(at: index ?? 0)
            let instances: EditOperation.DeleteNode.Instances = index == nil ? .detach : .refuse
            operations.append(.deleteNode(EditOperation.DeleteNode(nodeID: id, instances: instances)))
            detach(id)
        }
    }

    // MARK: - Phase 6

    /// Retypes every kept node that becomes a leaf, now that its children are gone —
    /// `updateKind` drops the child list a leaf cannot hold — then writes its
    /// remaining content.
    mutating func retypeToLeaves() {
        for (id, state) in keptChanges where isRetyped(id, to: state) && !state.node.kind.canHaveChildren {
            retype(id, to: state.node)
            lists[id] = .some(nil)
            writeContent(of: id, to: state.node)
        }
    }

    /// Gives each kept container left with no children the declared-ness the merge
    /// wants — `"children": []`, or no key — through `updateKind`'s
    /// ``EditOperation/UpdateKind/emptyChildren``, with the kind it has now.
    mutating func declareEmptyChildren() {
        for (id, state) in keptChanges where state.node.kind.canHaveChildren && (state.children ?? []).isEmpty {
            let declared = state.children != nil
            guard (list(of: id) != nil) != declared, let now = contentNow(of: id) else { continue }
            operations.append(.updateKind(EditOperation.UpdateKind(
                nodeID: id, kind: now.kind.withEmptyChildren(), emptyChildren: declared ? .declared : .absent
            )))
            lists[id] = .some(declared ? [] : nil)
        }
    }

    // MARK: - Shared

    /// Replaces a node's kind payload with `merged`'s, children stripped.
    private mutating func retype(_ id: String, to merged: PenNode) {
        operations.append(.updateKind(EditOperation.UpdateKind(nodeID: id, kind: merged.kind.withEmptyChildren())))
        if var node = contentNow(of: id) {
            node.kind = merged.kind.withEmptyChildren()
            current[id] = node
        }
    }
}
