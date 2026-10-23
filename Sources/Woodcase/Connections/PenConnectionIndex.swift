//
//  PenConnectionIndex.swift
//  Woodcase
//

import Foundation

/// Which connections a change to some nodes makes stale: the node → connections index an
/// editor reads to redraw the connectors that follow a moved card.
///
/// A connection's route depends on its two endpoints' boxes on the canvas, and an
/// endpoint's box moves when the endpoint moves or resizes, when any ancestor does — a
/// descendant moves with its card — and, for an endpoint inside a component instance
/// (`instance/child`), when the instance moves or its component changes. So the index keys
/// each connection under every node whose change can move one of its endpoints:
///
/// - each id the endpoint's path names — the instance and every id inside it, since a
///   change to a component's own `child` moves every instance's `instance/child`;
/// - every ancestor of each of those ids in the document;
/// - the component each named instance is of.
///
/// It over-approximates on purpose: a connection listed that did not need redrawing costs
/// a redraw; one missed leaves a stale connector. A connection is also listed for a change
/// to itself, and for a change to a node whose id an endpoint names before the node exists.
///
/// Build it from the document as written — the tree an edit applies to, with its instances
/// as `ref` nodes, so it knows each instance's component — and build it again when
/// connections are added or removed, or a node is reparented: it records the tree as it was.
public struct PenConnectionIndex: Friendly {
    /// Every connection's id, in document order.
    public let connectionIDs: [String]

    /// Each connection's place in ``connectionIDs``, for ordering a result.
    private let order: [String: Int]

    /// The connections whose route a change to each node can move, by node id.
    private let affected: [String: Set<String>]

    /// The connections that name each node id as an endpoint path, whole.
    private let attached: [String: Set<String>]

    /// Indexes every connection in `document`, at any depth.
    ///
    /// - Parameter document: The document.
    public init(_ document: PenDocument) {
        var parent: [String: String] = [:]
        var componentOf: [String: String] = [:]
        var connections: [(id: String, data: PenNode.ConnectionData)] = []
        var stack: [(node: PenNode, parent: String?)] = document.children.reversed().map { ($0, nil) }
        while let (node, parentID) = stack.popLast() {
            if let parentID { parent[node.id] = parentID }
            switch node.kind {
            case let .frame(data): stack += (data.children ?? []).reversed().map { ($0, node.id) }
            case let .group(data): stack += (data.children ?? []).reversed().map { ($0, node.id) }
            case let .ref(data): componentOf[node.id] = data.ref
            case let .connection(data): connections.append((node.id, data))
            default: break
            }
        }

        var affected: [String: Set<String>] = [:]
        var attached: [String: Set<String>] = [:]
        for (id, data) in connections {
            affected[id, default: []].insert(id)
            for endpoint in [data.source, data.target] {
                attached[endpoint.path, default: []].insert(id)
                for key in Self.keys(of: endpoint.path, parent: parent, componentOf: componentOf) {
                    affected[key, default: []].insert(id)
                }
            }
        }
        connectionIDs = connections.map(\.id)
        order = Dictionary(connections.enumerated().map { ($1.id, $0) }) { first, _ in first }
        self.affected = affected
        self.attached = attached
    }

    /// The connections whose route must be redrawn after a change to these nodes.
    ///
    /// - Parameter changedNodeIDs: The nodes an edit moved, resized, replaced, added or
    ///   removed, by id — an expanded instance's descendants by `instance/child` path, or
    ///   their component's own ids.
    /// - Returns: The connections, each once, in document order.
    public func connections(affectedBy changedNodeIDs: some Sequence<String>) -> [String] {
        var found: Set<String> = []
        for id in changedNodeIDs {
            found.formUnion(affected[id] ?? [])
        }
        return sorted(found)
    }

    /// The connections that name a node as one of their endpoints.
    ///
    /// - Parameter nodeID: The node's id, or an `instance/child` path.
    /// - Returns: The connections, in document order; a connection attached only to a
    ///   descendant of the node is not one.
    public func connections(attachedTo nodeID: String) -> [String] {
        sorted(attached[nodeID] ?? [])
    }

    /// `ids` in document order.
    private func sorted(_ ids: Set<String>) -> [String] {
        ids.sorted { (order[$0] ?? .max, $0) < (order[$1] ?? .max, $1) }
    }

    /// Every node id whose change can move the endpoint at `path`.
    private static func keys(of path: String, parent: [String: String], componentOf: [String: String]) -> Set<String> {
        var keys: Set<String> = [path]
        let segments = path.split(separator: "/").map(String.init)
        for segment in segments {
            var current: String? = segment
            while let id = current {
                keys.insert(id)
                if let component = componentOf[id] { keys.insert(component) }
                current = parent[id]
            }
        }
        return keys
    }
}
