//
//  EditableDocument+DetachPlan.swift
//  Woodcase
//

import Foundation

/// What a run of detaches will write, worked out before any of them runs.
///
/// A detach's ids are derived (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``), so the
/// subtree it will insert is known in advance. Every path that detaches — a plain
/// detach, a detaching delete, their collaborative forms — and every inverse prepared
/// for one asks this one function, so what the inverse names is what the detach does.
extension EditableDocument {
    /// One planned detach: the ref, where it sits, and the subtree that will replace it.
    struct PlannedDetach {
        /// The ref being detached.
        var refID: String
        /// The ref's parent, or `nil` at the root.
        var parentID: String?
        /// The ref's index among its siblings.
        var index: Int?
        /// The expansion with its derived ids, ready to insert in the ref's place.
        var subtree: PenNode
        /// Expanded id → derived id, for every node of the subtree.
        var idMapping: [String: String]
        /// What a connector end names → derived id: ``idMapping``, and each instance's
        /// path (`ref`, `ref/row`) → the derived id of the root it expands to, the
        /// spelling a connector end uses for an instance (``connectorRewrites(for:)``).
        var endMapping: [String: String]
    }

    /// The ids no detach may mint: every id the document holds, and in a collaborative
    /// session every id the replica has deleted, which a peer still holds as a tombstone.
    var detachTakenIDs: Set<String> {
        var taken = Set(nodes.keys)
        if let tombstones = crdtDocument?.tombstones {
            taken.formUnion(tombstones)
        }
        return taken
    }

    /// Plans a run of detaches, in order.
    ///
    /// In collaborative mode the ids are namespaced by this replica's peer id, so two peers
    /// detaching one instance concurrently create distinct nodes. Each plan avoids the ids
    /// the ones before it take. The avoided set only grows —
    /// a ref's own id stays avoided after its detach removes it — so the plans do not
    /// depend on how the earlier detaches are carried out, only on the document they
    /// start from.
    ///
    /// - Parameters:
    ///   - refIDs: The refs to detach, in the order they will be detached.
    ///   - dropping: Components whose instances are left out of every expansion — the
    ///     ones a delete is removing (see ``detachPlans(deleting:)``).
    /// - Returns: One plan per ref.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    func detachPlans(for refIDs: [String], dropping: Set<String> = []) throws -> [PlannedDetach] {
        var taken = detachTakenIDs
        var plans: [PlannedDetach] = []
        for refID in refIDs {
            try requireRef(refID)
            let expanded = try Self.removingInstances(of: dropping, from: detachExpansion(of: refID, expanding: dropping))
            let ids = SubtreeIDPlan.detaching(
                expanded, refID: refID, replica: crdtDocument?.peerID, avoiding: taken
            )
            taken.formUnion(ids.ids)

            let parentID = parents[refID]
            let index: Int? = if let parentID {
                children[parentID]?.firstIndex(of: refID)
            } else {
                rootOrder.firstIndex(of: refID)
            }
            plans.append(PlannedDetach(
                refID: refID,
                parentID: parentID,
                index: index,
                subtree: ids.applied(to: expanded),
                idMapping: ids.replacements,
                endMapping: Self.endMapping(of: expanded, refID: refID, idMapping: ids.replacements)
            ))
        }
        return plans
    }

    /// Plans the detaches a delete under ``EditOperation/DeleteNode/Instances/detach``
    /// makes: one per instance it would strand.
    ///
    /// Each detach expands its instance one level, as a plain detach does, except that
    /// an instance nested in it of a component the delete removes would be stranded
    /// too, so it expands in turn. An instance of a component that renders itself still
    /// expands with the inner instance that closes the cycle left as a `ref` — the
    /// expansion stops where it would repeat — and once the delete removes that
    /// component such a ref would name nothing, so it is left out: what it drew is going
    /// away with the delete. No ref survives that names a deleted component, and the
    /// delete's inverse, which reads these same plans, puts the instance back as it was.
    ///
    /// - Parameter op: The delete.
    /// - Returns: One plan per stranded instance; empty for a delete that strands none.
    /// - Throws: ``EditingError/componentHasInstances(componentID:instanceIDs:)`` for a
    ///   delete that strands instances it may not detach, as ``instancesToDetach(for:)``.
    func detachPlans(deleting op: EditOperation.DeleteNode) throws -> [PlannedDetach] {
        let stranded = try instancesToDetach(for: op)
        guard !stranded.isEmpty else { return [] }
        let removed = Set(descendantIDs(of: op.nodeID).filter { componentRegistry[$0] != nil })
        return try detachPlans(for: stranded, dropping: removed)
    }

    /// What a detach writes in an instance's place: the instance expanded one level.
    ///
    /// Its overrides are baked into the nodes its component wrote, and the instances
    /// nested in it stay instances, linked to their components, each carrying the
    /// overrides the detached instance made inside it as its own `descendants`
    /// (``PenRefExpander/expandInstanceLevel(refNode:registry:cache:expandingNestedInstancesOf:)``;
    /// Ben, 2026-10-27, Penumbra spec §13). A nested instance of a component in
    /// `components` would name nothing once the delete removing it lands, so it expands
    /// in turn.
    ///
    /// - Parameters:
    ///   - refID: The ref being detached.
    ///   - components: Components whose nested instances expand too.
    /// - Returns: The expansion, its ids the ref's prefixed spelling.
    /// - Throws: ``EditingError/nodeNotFound(id:)``.
    private func detachExpansion(of refID: String, expanding components: Set<String>) throws -> PenNode {
        try PenRefExpander.expandInstanceLevel(
            refNode: requireNode(refID),
            registry: materializedComponents(),
            cache: PenRefExpander.ResolverCache(loops: componentLoopIndex),
            expandingNestedInstancesOf: components
        )
    }

    /// An expansion without the instances of some components.
    ///
    /// - Parameters:
    ///   - components: The components whose instances to leave out.
    ///   - expanded: The expansion.
    /// - Returns: The expansion, every `ref` naming one of `components` removed below its
    ///   root.
    private static func removingInstances(of components: Set<String>, from expanded: PenNode) -> PenNode {
        guard !components.isEmpty else { return expanded }
        return PenTreeRewrite.rewrite(expanded, context: true) { node, isRoot in
            if !isRoot, case let .ref(data) = node.kind, components.contains(data.ref) { return .drop }
            return .descend(node, false)
        } ?? expanded
    }
}
