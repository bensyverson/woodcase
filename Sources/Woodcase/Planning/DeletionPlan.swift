//
//  DeletionPlan.swift
//  Woodcase
//

import Foundation

/// What ``EditPlanner/planDelete(nodeIDs:in:)`` decided a delete becomes: the edits, the
/// nodes they delete, and the connectors that go with those nodes.
///
/// Submit ``operations`` as one edit, so one undo brings the nodes and their connectors
/// back together.
///
/// ```swift
/// let plan = try EditPlanner.planDelete(nodeIDs: ["Card"], in: document)
/// plan.connectorIDs   // ["K1", "K3"], attached to Card or to something inside it
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// ```
public struct DeletionPlan: Friendly {
    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - operations: The deletes, connectors first.
    ///   - nodeIDs: The nodes asked for, each once, none inside another.
    ///   - connectorIDs: The connectors deleted because an end was.
    public init(operations: [EditOperation], nodeIDs: [String], connectorIDs: [String]) {
        self.operations = operations
        self.nodeIDs = nodeIDs
        self.connectorIDs = connectorIDs
    }

    /// The deletes, in order: each connector taken along, then each node asked for.
    ///
    /// Connectors go first so that the undo, which runs the reverse, puts the nodes back
    /// before the connectors that name them.
    public var operations: [EditOperation]

    /// The nodes asked for, as stored ids in the order given, each once and none inside
    /// another — a node inside one already deleted goes with it.
    public var nodeIDs: [String]

    /// The connectors deleted because an end was attached to a deleted node or to
    /// anything inside one, in document order. A connector among ``nodeIDs``, or inside
    /// one of them, is not listed: it is already deleted.
    public var connectorIDs: [String]
}
