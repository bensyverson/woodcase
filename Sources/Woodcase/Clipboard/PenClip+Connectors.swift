//
//  PenClip+Connectors.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// The connectors a copy carries, as the clip holds them: each one's ends renamed to
    /// the ids the copies took in the clip.
    ///
    /// An end on a node drawn inside an instance names its expanded id, which the
    /// detached copy replaced; an end whose first id is a copied root the clip renumbered
    /// follows it, and the rest of its path — the ids inside an instance — stays, since
    /// they are the component's.
    ///
    /// - Parameters:
    ///   - ids: The connectors, from ``EditPlanner/connectorIDs(enclosedBy:in:)``.
    ///   - document: The source document.
    ///   - drawn: Each drawn node's expanded id → its copy's id.
    ///   - renumbered: Each renumbered id → its new id.
    /// - Returns: The connectors, in the same order.
    /// - Throws: ``EditingError/nodeNotFound(id:)``, which a connector the query found
    ///   does not raise.
    static func carriedConnectors(
        _ ids: [String],
        in document: EditableDocument,
        drawn: [String: String],
        renumbered: [String: String]
    ) throws -> [PenNode] {
        try ids.map { id in
            var node = try document.materializeSubtree(rootID: id)
            guard case var .connection(data) = node.kind else { return node }
            for end in [\PenNode.ConnectionData.source, \.target] {
                data[keyPath: end].path = renamed(data[keyPath: end].path, drawn: drawn, renumbered: renumbered)
            }
            node.kind = .connection(data)
            return node
        }
    }

    /// One end's path in the clip.
    private static func renamed(_ path: String, drawn: [String: String], renumbered: [String: String]) -> String {
        var steps = (drawn[path] ?? path).split(separator: NodeAddress.separator, omittingEmptySubsequences: false)
            .map(String.init)
        if let first = steps.first, let new = renumbered[first] {
            steps[0] = new
        }
        return steps.joined(separator: String(NodeAddress.separator))
    }
}
