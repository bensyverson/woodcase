//
//  PenClip+Selected.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// One node to copy, found: its subtree and where it sits.
    struct Selected: Friendly {
        /// What the selection knows it by: a stored node's id, or the expanded id of a
        /// node drawn inside an instance.
        var key: String

        /// The subtree to copy: materialized from the store, or cut from the instance's
        /// expansion with its expanded ids.
        var subtree: PenNode

        /// The instance a drawn node is cut from, or `nil` for a stored node.
        var instanceID: String?

        /// The keys of everything above the node: stored ancestors, and for a drawn node
        /// the instance and the nodes of its expansion above it.
        var ancestors: Set<String>

        /// Where the node falls in document order: its own position, or for a drawn
        /// node its instance's, then its place in the expansion.
        var order: [Int]

        /// The id the node is laid out under in the expanded document.
        var expandedID: String

        /// Whether the node is a root of the source document, already at its canvas
        /// position.
        var isRoot: Bool

        /// The parent it sits in: a stored node's id, or for a drawn node the expanded id
        /// of the node it is drawn under; `nil` for a root.
        var parentID: String?

        /// The stored root above it, or `nil` for a root.
        var boardID: String?
    }

    /// Finds every node to copy, drops each one another copied node holds, and orders
    /// the rest as the document does.
    ///
    /// - Parameters:
    ///   - nodeIDs: The ids as given.
    ///   - document: The source document.
    ///   - position: Each stored id's index in document order.
    /// - Returns: The selection, in document order.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` for an id that names no node.
    static func selection(
        _ nodeIDs: [String],
        in document: EditableDocument,
        position: [String: Int]
    ) throws -> [Selected] {
        var found: [Selected] = []
        var keys: Set<String> = []
        for id in nodeIDs {
            let node = try selected(id, in: document, position: position)
            if keys.insert(node.key).inserted {
                found.append(node)
            }
        }
        return found
            .filter { $0.ancestors.isDisjoint(with: keys) }
            .sorted { $0.order.lexicographicallyPrecedes($1.order) }
    }

    /// Finds one node to copy.
    ///
    /// - Parameters:
    ///   - id: A stored id or an expanded one.
    ///   - document: The source document.
    ///   - position: Each stored id's index in document order.
    /// - Returns: The node.
    /// - Throws: ``EditingError/nodeNotFound(id:)``.
    private static func selected(
        _ id: String,
        in document: EditableDocument,
        position: [String: Int]
    ) throws -> Selected {
        let resolved: ResolvedNodeAddress? = document.nodes[id] != nil ? .node(id: id) : document.resolve(expandedID: id)
        switch resolved {
        case let .node(storedID)?:
            let ancestors = storedAncestors(of: storedID, in: document)
            return try Selected(
                key: storedID,
                subtree: document.materializeSubtree(rootID: storedID),
                instanceID: nil,
                ancestors: Set(ancestors),
                order: [position[storedID] ?? Int.max],
                expandedID: document.expandedID(of: .node(id: storedID)),
                isRoot: document.parents[storedID] == nil,
                parentID: ancestors.first,
                boardID: ancestors.last
            )
        case let .instanceDescendant(refID, _)?:
            return try drawn(id, inInstance: refID, of: document, position: position)
        case nil:
            throw EditingError.nodeNotFound(id: id)
        }
    }

    /// Cuts a drawn node out of its instance's expansion.
    ///
    /// - Parameters:
    ///   - expandedID: The node's expanded id.
    ///   - refID: The stored instance it is drawn inside.
    ///   - document: The source document.
    ///   - position: Each stored id's index in document order.
    /// - Returns: The node.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` when the expansion has no such node.
    private static func drawn(
        _ expandedID: String,
        inInstance refID: String,
        of document: EditableDocument,
        position: [String: Int]
    ) throws -> Selected {
        let expansion = try document.expandRef(nodeID: refID).expandedNode
        let outside = [refID] + storedAncestors(of: refID, in: document)
        var index = 0
        // Pre-order from a work list, carrying each node's expanded ancestors.
        var pending: [(node: PenNode, above: [String])] = [(expansion, [])]
        while let (node, above) = pending.popLast() {
            index += 1
            if node.id == expandedID {
                return Selected(
                    key: expandedID,
                    subtree: node,
                    instanceID: refID,
                    ancestors: Set(outside + above),
                    order: [position[refID] ?? Int.max, index],
                    expandedID: expandedID,
                    isRoot: false,
                    parentID: above.last ?? refID,
                    boardID: outside.last
                )
            }
            pending.append(contentsOf: node.kind.inlineChildren.reversed().map { ($0, above + [node.id]) })
        }
        throw EditingError.nodeNotFound(id: expandedID)
    }

    /// A stored node's ancestors, nearest first.
    ///
    /// - Parameters:
    ///   - id: The stored node.
    ///   - document: The source document.
    /// - Returns: Its ancestors' ids.
    private static func storedAncestors(of id: String, in document: EditableDocument) -> [String] {
        var result: [String] = []
        var current = id
        while let parent = document.parents[current], !result.contains(parent) {
            result.append(parent)
            current = parent
        }
        return result
    }
}
