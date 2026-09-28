//
//  EditableDocument+NamePath.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The full path from a node's root down to it, one segment per ancestor.
    ///
    /// This is the reverse of ``resolve(_:tags:)-(String,_)`` and the form every error
    /// message and tree row uses to name a node: `"Dashboard/Header/Title"`.
    ///
    /// Each segment is the node's `common.name`, except where that name could not be
    /// read back as *this* node — it is missing or empty, contains a `/`, or begins
    /// with `#` or `@`. Those segments fall back to the id marker
    /// ``NodeAddress/marker(forID:)`` (`"#Unn01"`), which the resolver accepts as that
    /// exact node. The path therefore always resolves to the node it describes, though
    /// a shorter address may of course be ambiguous.
    ///
    /// - Parameter nodeID: The node to describe.
    /// - Returns: The node's full name path. For an id that is not in the document,
    ///   its marker alone (`"#gone1"`).
    func namePath(of nodeID: String) -> String {
        guard nodes[nodeID] != nil else { return NodeAddress.marker(forID: nodeID) }
        let chain = Array(ancestors(of: nodeID).reversed()) + [nodeID]
        return chain
            .map(pathSegment(for:))
            .joined(separator: String(NodeAddress.separator))
    }

    /// The full path to a node inside a component instance.
    ///
    /// The instance's own path, then the steps of the `descendants` key — so
    /// `"Bdg01/Cnt01"` under the ref `Nav01` reads `"Dashboard/Body/Nav/Badge/Count"`.
    /// Like ``namePath(of:)-(String)``, the result resolves back to the same instance
    /// descendant.
    ///
    /// A key step is one id, and it says nothing about the containers between that node
    /// and its component's root — `"Ttl03"` is a legal key for a text inside a group. A
    /// name path has to name every one of them, because names resolve as consecutive
    /// parent→child steps, so each key step expands to its own path within the
    /// component that holds it.
    ///
    /// A step naming a child the instance **injected** into a slot expands the same
    /// way, through the slot frame that holds it: `"Note0"` under `Inst0` reads
    /// `"Page/Filled/Body/Note"`.
    ///
    /// - Parameters:
    ///   - descendantKey: The key as stored in the ref's `descendants` map.
    ///   - refID: The id of the ref node holding that map.
    /// - Returns: The descendant's full name path.
    func namePath(ofDescendant descendantKey: String, in refID: String) -> String {
        var chain = [refID]
        var parts = [namePath(of: refID)]
        for step in descendantKey.split(separator: NodeAddress.separator).map(String.init) {
            parts += componentSegments(to: step, insideInstances: chain)
            chain.append(step)
        }
        return parts.joined(separator: String(NodeAddress.separator))
    }

    /// The full path to whatever an address resolved to.
    ///
    /// - Parameter resolved: A resolved address.
    /// - Returns: Its full name path.
    func namePath(of resolved: ResolvedNodeAddress) -> String {
        switch resolved {
        case let .node(id): namePath(of: id)
        case let .instanceDescendant(refID, key): namePath(ofDescendant: key, in: refID)
        }
    }
}

// MARK: - Segments

extension EditableDocument {
    /// The segments naming one node inside its component: every step from just below
    /// the component root down to the node itself.
    ///
    /// The component root is the nearest reusable ancestor, which is where an
    /// instance's coordinate system starts — the ref stands in for it, so it is never
    /// a segment.
    ///
    /// A node the instance **injected** is in no store, so its containers cannot be
    /// read from one: ``injectedNodes(insideInstances:)`` carries the segments down
    /// from the slot frame it was written into.
    ///
    /// - Parameters:
    ///   - nodeID: The node one step of a `descendants` key names.
    ///   - chain: The `ref` node ids the step sits inside, outermost first.
    /// - Returns: One segment per step. A node that is neither in the document nor
    ///   injected is its marker alone, so an unresolved key still prints something
    ///   readable.
    func componentSegments(to nodeID: String, insideInstances chain: [String]) -> [String] {
        if let injected = injectedNodes(insideInstances: chain)[nodeID] { return injected.segments }
        guard componentNode(nodeID) != nil else { return [NodeAddress.marker(forID: nodeID)] }
        let inside = componentAncestors(of: nodeID).prefix { reusableComponent($0) == nil }
        return (inside.reversed() + [nodeID]).map(pathSegment(for:))
    }

    /// The segments naming one node of a component, read from the flat store alone.
    ///
    /// - Parameter nodeID: The node one step of a `descendants` key names.
    /// - Returns: One segment per step from just below the component root.
    func componentSegments(to nodeID: String) -> [String] {
        componentSegments(to: nodeID, insideInstances: [])
    }

    /// One segment of a name path: the node's name, or its id marker when the name
    /// would not read back as this node.
    private func pathSegment(for nodeID: String) -> String {
        guard let node = componentNode(nodeID) else { return NodeAddress.marker(forID: nodeID) }
        return pathSegment(of: node)
    }

    /// One segment of a name path, for a node the caller already holds — the only form
    /// an injected node has.
    ///
    /// - Parameter node: The node to name.
    /// - Returns: Its name, or its id marker when the name would not read back as it.
    func pathSegment(of node: PenNode) -> String {
        guard let name = node.common.name, isUsableAsSegment(name) else {
            return NodeAddress.marker(forID: node.id)
        }
        return name
    }

    /// Whether a name can stand as a path segment without changing what it addresses.
    private func isUsableAsSegment(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return first != NodeAddress.idPrefix
            && first != NodeAddress.tagPrefix
            && !name.contains(NodeAddress.separator)
    }
}
