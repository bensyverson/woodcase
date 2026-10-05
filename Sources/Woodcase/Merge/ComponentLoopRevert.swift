//
//  ComponentLoopRevert.swift
//  Woodcase
//

import Foundation

/// Undoes one external change to one node, in a copy of the external document, because
/// merged with the local side it would close a component loop — and says what was left
/// out. See ``DocumentMerge/keepingComponentLoopsOut(base:ours:theirs:merge:)``.
///
/// Not `Friendly`, on purpose: it holds the live documents of one merge.
struct ComponentLoopRevert {
    /// The node whose external change may be the one to leave out.
    let id: String

    /// The local document with the merge's operations replayed on it.
    let merged: EditableDocument

    /// The common ancestor.
    let base: EditableDocument

    /// The local side.
    let ours: EditableDocument

    /// The external side, as the merge last read it.
    let theirs: EditableDocument

    /// The external document without the node's change, and the conflict reporting it;
    /// `nil` when the merge holds the node as the local side does, or the change is not
    /// the external side's.
    func run() -> (EditableDocument, MergeConflict)? {
        guard merged.nodes[id] != nil, let external = theirs.nodes[id] else { return nil }
        if ours.nodes[id] == nil {
            return removingInsert()
        }
        if merged.parents[id] != ours.parents[id], theirs.parents[id] == merged.parents[id] {
            return restoringParent()
        }
        guard let local = ours.nodes[id], merged.nodes[id] != local, external == merged.nodes[id] else { return nil }
        return restoringContent(local: local, external: external)
    }

    /// Drops a node the external side inserted, with its subtree.
    private func removingInsert() -> (EditableDocument, MergeConflict)? {
        let copy = EditableDocument(from: theirs.materialize())
        let subtree = try? NodePropertyCodec.encode(theirs.materializeSubtree(rootID: id))
        let doomed = copy.descendantIDs(of: id)
        if let parent = copy.parents[id] {
            copy.children[parent]?.removeAll { $0 == id }
        } else {
            copy.rootOrder.removeAll { $0 == id }
        }
        for node in doomed {
            copy.nodes[node] = nil
            copy.parents[node] = nil
            copy.children[node] = nil
            copy.updateComponentRegistry(for: node)
        }
        return (copy, MergeConflict(subject: .existence(nodeID: id), kind: .wouldCloseComponentLoop, theirs: subtree))
    }

    /// Puts a node the external side moved back under the parent the base gave it.
    private func restoringParent() -> (EditableDocument, MergeConflict)? {
        let copy = EditableDocument(from: theirs.materialize())
        let original: String? = base.nodes[id] != nil ? base.parents[id] : ours.parents[id]
        if let original, copy.nodes[original] == nil { return nil }
        if let current = copy.parents[id] {
            copy.children[current]?.removeAll { $0 == id }
        } else {
            copy.rootOrder.removeAll { $0 == id }
        }
        if let original {
            copy.children[original, default: []].append(id)
            copy.parents[id] = original
        } else {
            copy.rootOrder.append(id)
            copy.parents[id] = nil
        }
        let conflict = MergeConflict(
            subject: .parent(nodeID: id), kind: .wouldCloseComponentLoop,
            base: base.nodes[id].map { _ in Self.parentValue(base.parents[id]) },
            ours: Self.parentValue(ours.parents[id]), theirs: Self.parentValue(theirs.parents[id])
        )
        return (copy, conflict)
    }

    /// Puts back the content the base gave a node the external side rewrote.
    private func restoringContent(local: PenNode, external: PenNode) -> (EditableDocument, MergeConflict)? {
        let copy = EditableDocument(from: theirs.materialize())
        copy.nodes[id] = base.nodes[id] ?? local
        copy.updateComponentRegistry(for: id)
        let path = Self.path(changedFrom: local, to: external)
        let conflict = MergeConflict(
            subject: .property(nodeID: id, path: path), kind: .wouldCloseComponentLoop,
            base: base.nodes[id].map { ThreeWayResolver.value(at: path, of: $0) },
            ours: ThreeWayResolver.value(at: path, of: local),
            theirs: ThreeWayResolver.value(at: path, of: external)
        )
        return (copy, conflict)
    }

    /// The property that names what a rewrite changed in the component graph: the `ref`,
    /// then the overrides, then `reusable`.
    private static func path(changedFrom local: PenNode, to external: PenNode) -> String {
        if case let .ref(before) = local.kind, case let .ref(after) = external.kind {
            if before.ref != after.ref { return "kind.ref" }
            if before.descendants != after.descendants { return "kind.descendants" }
            if before.rootOverrides != after.rootOverrides { return "kind.rootOverrides" }
        }
        if local.common.reusable != external.common.reusable { return "common.reusable" }
        return local.kind.typeName == external.kind.typeName ? "kind.ref" : "type"
    }

    /// A parent as a conflict carries it: its id, or `null` for the top level.
    private static func parentValue(_ parent: String?) -> AnyCodable {
        parent.map(AnyCodable.string) ?? .null
    }
}
