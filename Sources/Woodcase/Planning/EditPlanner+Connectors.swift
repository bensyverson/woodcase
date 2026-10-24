//
//  EditPlanner+Connectors.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// The connectors with an end attached to one of `removed`, none of them among it, in
    /// document order: the connectors an edit that removes those nodes must remove too.
    ///
    /// An end's path names a node by id, or steps into instances by id
    /// (`instance/child`); it is attached to a removed node when any of those ids is one.
    /// Connectors are found at any depth, though Pen keeps them only at the top level.
    /// ``planDelete(nodeIDs:in:)`` and ``planUngroup(groupID:in:layout:)`` ask this.
    ///
    /// - Parameters:
    ///   - removed: Every node an edit removes, descendants included, as stored ids.
    ///   - document: The document, before the edit.
    /// - Returns: The connectors to delete with them.
    static func connectorIDs(attachedTo removed: Set<String>, in document: EditableDocument) -> [String] {
        guard !removed.isEmpty else { return [] }
        let attached: Set<String> = Set(document.nodes.compactMap { id, node in
            guard !removed.contains(id), case let .connection(data) = node.kind else { return nil }
            let ends = [data.source.path, data.target.path]
            let touches = ends.contains { path in
                path.split(separator: NodeAddress.separator).contains { removed.contains(String($0)) }
            }
            return touches ? id : nil
        })
        guard !attached.isEmpty else { return [] }
        return document.nodeIDsInDocumentOrder().filter(attached.contains)
    }

    /// The connectors a copy of some nodes carries: those whose two ends are both inside
    /// the copied nodes, in document order.
    ///
    /// Copy, and so Cut, carries every connector whose two ends are both inside the copied
    /// nodes — a copied node or anything inside it — whether or not the connector was
    /// selected, and a connector with one end outside the copy is not carried (Ben's
    /// ruling of 2026-10-23, Penumbra spec §11). Duplicate and an Option-drag copy follow
    /// the same rule, so it lives here once: ``PenClip/extract(nodeIDs:from:documentID:)``
    /// asks this, and so should any other copy.
    ///
    /// - Parameters:
    ///   - nodeIDs: The copied nodes, as an editor selects them: stored ids, or the
    ///     expanded ids of nodes drawn inside an instance. An id naming nothing is
    ///     ignored.
    ///   - document: The document they are in.
    /// - Returns: The connectors, none among the copied nodes or inside one.
    static func connectorIDs(enclosedBy nodeIDs: [String], in document: EditableDocument) -> [String] {
        let inside = EnclosedNodes(nodeIDs, in: document)
        guard !inside.isEmpty else { return [] }
        let enclosed: Set<String> = Set(document.nodes.compactMap { id, node in
            guard !inside.stored.contains(id), case let .connection(data) = node.kind else { return nil }
            return inside.encloses(data.source.path) && inside.encloses(data.target.path) ? id : nil
        })
        guard !enclosed.isEmpty else { return [] }
        return document.nodeIDsInDocumentOrder().filter(enclosed.contains)
    }
}

/// Every node some copied nodes take with them, as a connector end names it.
private struct EnclosedNodes {
    /// The stored nodes copied, and every stored node inside one.
    var stored: Set<String> = []

    /// The expanded ids of the nodes drawn inside an instance that were copied, and of
    /// everything drawn inside one.
    var drawn: Set<String> = []

    /// Whether nothing was found.
    var isEmpty: Bool {
        stored.isEmpty && drawn.isEmpty
    }

    /// Finds the nodes.
    ///
    /// - Parameters:
    ///   - nodeIDs: Stored or expanded ids; one naming nothing is skipped.
    ///   - document: The document.
    init(_ nodeIDs: [String], in document: EditableDocument) {
        for id in nodeIDs {
            let resolved: ResolvedNodeAddress? = document.nodes[id] != nil
                ? .node(id: id) : document.resolve(expandedID: id)
            switch resolved {
            case let .node(storedID)?:
                stored.formUnion(document.descendantIDs(of: storedID))
            case let .instanceDescendant(refID, _)?:
                guard let expansion = try? document.expandRef(nodeID: refID).expandedNode,
                      let node = Self.find(id, in: expansion) else { continue }
                drawn.formUnion(Self.ids(in: node))
            case nil:
                continue
            }
        }
    }

    /// Whether a connector end names one of the nodes: a path whose first id is a stored
    /// node taken (the node, or a node inside an instance taken), or a drawn node taken.
    func encloses(_ path: String) -> Bool {
        let first = path.split(separator: NodeAddress.separator, maxSplits: 1).first.map(String.init) ?? path
        return stored.contains(first) || drawn.contains(path)
    }

    /// The node of a subtree with an id, found pre-order from a work list.
    private static func find(_ id: String, in root: PenNode) -> PenNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if node.id == id { return node }
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return nil
    }

    /// Every id in a subtree.
    private static func ids(in root: PenNode) -> [String] {
        var ids: [String] = []
        var pending = [root]
        while let node = pending.popLast() {
            ids.append(node.id)
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return ids
    }
}
