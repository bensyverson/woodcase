//
//  EditRefusal+Detail.swift
//  Woodcase
//

import Foundation

public extension EditRefusal {
    /// What a refusal names, as values: the loop a move would close, the component whose
    /// instances a removal would orphan, the nodes an address could mean.
    ///
    /// The structured twin of what ``EditRefusal/message`` spells, so an editor can name
    /// the components in its own words, or offer the candidates, without parsing the
    /// sentence or replaying the edit.
    ///
    /// ```swift
    /// if case let .componentLoop(loop)? = refusal.detail {
    ///     loop.description   // "Status badge → Profile card → Status badge"
    /// }
    /// ```
    enum Detail: Friendly {
        /// The loop the edit would close (``EditRefusal/Code/wouldCloseComponentLoop``):
        /// its components in render order, starting from the one the edit writes into —
        /// each renders the next, and the last renders the first. A component that would
        /// render itself is the loop's only member. Each member is named by its `name`,
        /// or its id when it has none.
        case componentLoop(ComponentLoop)

        /// The component a removal would turn into a plain frame, and the instances that
        /// point at it (``EditRefusal/Code/componentHasInstances``).
        case componentHasInstances(componentID: String, instanceIDs: [String])

        /// The component a replacement would give a different type, the types, and the
        /// instances that point at it (``EditRefusal/Code/componentTypeChange``).
        case componentTypeChange(componentID: String, from: String, to: String, instanceIDs: [String])

        /// The node a move would put inside itself, and the parent it named
        /// (``EditRefusal/Code/wouldCreateCycle``): the parent is the node or one of its
        /// descendants.
        case wouldCreateCycle(nodeID: String, targetParentID: String)

        /// The nodes the address could have meant: every match of an ambiguous address,
        /// the near misses of one naming nothing, or what an instance's component holds
        /// for an override naming nothing there. Each is addressable by its
        /// ``NodeAddressCandidate/id``.
        case candidates([NodeAddressCandidate])
    }
}
