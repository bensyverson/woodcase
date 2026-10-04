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
    /// - Parameter refIDs: The refs to detach, in the order they will be detached.
    /// - Returns: One plan per ref.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    func detachPlans(for refIDs: [String]) throws -> [PlannedDetach] {
        var taken = detachTakenIDs
        var plans: [PlannedDetach] = []
        for refID in refIDs {
            try requireRef(refID)
            let expanded = try expandRef(nodeID: refID).expandedNode
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
                idMapping: ids.replacements
            ))
        }
        return plans
    }
}
