//
//  EditPlanner+ConnectorCopies.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Copies of the connectors a copy of some nodes carries
    /// (``connectorIDs(enclosedBy:in:)``): each with a fresh id and its ends rewritten,
    /// everything else as the original has it.
    ///
    /// - Parameters:
    ///   - connectorIDs: The connectors to copy, in the order to insert them.
    ///   - document: The document they are in, before the copy.
    ///   - taken: Every id in use, the copies' ids added.
    ///   - end: The path an end of a copy names, given the original's.
    /// - Returns: The copies, in the same order; an id naming no connector is skipped.
    static func connectorCopies(
        of connectorIDs: [String],
        in document: EditableDocument,
        taken: inout Set<String>,
        end: (String) -> String
    ) -> [PenNode] {
        connectorIDs.compactMap { id in
            guard let original = document.node(id: id), case var .connection(data) = original.kind else { return nil }
            data.source.path = end(data.source.path)
            data.target.path = end(data.target.path)
            let fresh = PenID.generate(avoiding: taken)
            taken.insert(fresh)
            return PenNode(id: fresh, common: original.common, kind: .connection(data), extras: original.extras)
        }
    }

    /// A connector end's path with each step mapped through old id → new id, the way a
    /// copy renames the nodes it names: `Card/Label` follows `Card`'s copy, and a step
    /// naming a node in a copied fill follows that node's.
    ///
    /// - Parameters:
    ///   - path: The end's path, `/`-separated ids.
    ///   - ids: Old id → new id.
    /// - Returns: The path, each step the map names replaced.
    static func mappingSteps(of path: String, through ids: [String: String]) -> String {
        guard !ids.isEmpty else { return path }
        return path.split(separator: NodeAddress.separator, omittingEmptySubsequences: false)
            .map { ids[String($0)] ?? String($0) }
            .joined(separator: String(NodeAddress.separator))
    }

    /// Each connection among some stored copies with its ends mapped through the copy's
    /// ids, so a duplicated connector whose ends were copied too follows them.
    ///
    /// - Parameters:
    ///   - operations: The copies' inserts.
    ///   - ends: The path an end of a copy names, given the original's.
    /// - Returns: The inserts, connections rewritten.
    static func followingCopies(
        _ operations: [EditOperation], ends: (String) -> String
    ) -> [EditOperation] {
        operations.map { operation in
            guard case var .insertNode(insert) = operation, case var .connection(data) = insert.node.kind else {
                return operation
            }
            data.source.path = ends(data.source.path)
            data.target.path = ends(data.target.path)
            insert.node = PenNode(id: insert.node.id, common: insert.node.common, kind: .connection(data), extras: insert.node.extras)
            return .insertNode(insert)
        }
    }
}
