//
//  EditableDocument+DetachConnectors.swift
//  Woodcase
//

import Foundation

/// The connector ends a detach rewrites.
///
/// A detach gives every node of the instance a derived id
/// (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``), the root included, so a
/// connector end naming the instance (`Card`), a node drawn inside it (`Card/title`), a
/// node of one of its slot fills, or a node inside an instance nested in it would name
/// nothing afterward. The detach rewrites each such end to the detached copy's id — for a
/// node inside a nested instance, which the detach leaves an instance, the path through
/// that instance's copy (`ok/badge/pip` becomes `<badge copy>/pip`) — in the same edit: the flat store writes the rewrite with the expansion, a collaborative detach
/// replicates it with the delete and insert it decomposes into, and the detach's inverse
/// puts the ends back. Keeping the root's own id instead would split the collaborative
/// detach, whose delete tombstones the ref's id (integrator's ruling, session 48).
extension EditableDocument {
    /// One connector a run of detaches rewrites.
    struct DetachedConnector {
        /// The connector.
        var connectorID: String
        /// Its kind before the run.
        var before: PenNode.Kind
        /// Its kind after the run, its ends renamed.
        var after: PenNode.Kind
    }

    /// The connectors a run of detaches rewrites, in document order, read from the
    /// document as it stands.
    ///
    /// Each end is passed through every plan in turn, so a connector with one end in
    /// each of two instances detached together comes out with both ends rewritten.
    ///
    /// - Parameter plans: The detaches, in the order they run.
    /// - Returns: The connectors whose ends change, before and after.
    func detachedConnectors(for plans: [PlannedDetach]) -> [DetachedConnector] {
        guard !plans.isEmpty else { return [] }
        var rewritten: [String: DetachedConnector] = [:]
        for (id, node) in nodes {
            guard case var .connection(data) = node.kind else { continue }
            for plan in plans {
                data.source.path = Self.detachedPath(data.source.path, by: plan)
                data.target.path = Self.detachedPath(data.target.path, by: plan)
            }
            let after = PenNode.Kind.connection(data)
            guard after != node.kind else { continue }
            rewritten[id] = DetachedConnector(connectorID: id, before: node.kind, after: after)
        }
        guard !rewritten.isEmpty else { return [] }
        return nodeIDsInDocumentOrder().compactMap { rewritten[$0] }
    }

    /// The edits that rewrite the connector ends one detach leaves naming its instance.
    ///
    /// - Parameter plan: The detach, from ``detachPlans(for:)``.
    /// - Returns: One ``EditOperation/updateKind(_:)`` per connector it rewrites.
    func connectorRewrites(for plan: PlannedDetach) -> [EditOperation] {
        detachedConnectors(for: [plan]).map { connector in
            .updateKind(EditOperation.UpdateKind(nodeID: connector.connectorID, kind: connector.after))
        }
    }

    /// The edits that put back the connector ends a run of detaches rewrites, for its
    /// inverse.
    ///
    /// - Parameter plans: The detaches, in the order they run.
    /// - Returns: One ``EditOperation/updateKind(_:)`` per connector, restoring its kind.
    func connectorRestores(for plans: [PlannedDetach]) -> [EditOperation] {
        detachedConnectors(for: plans).map { connector in
            .updateKind(EditOperation.UpdateKind(nodeID: connector.connectorID, kind: connector.before))
        }
    }

    /// The connectors among some a delete would take that detaching some instances first
    /// keeps instead.
    ///
    /// A delete takes a connector with an end naming a removed node, a component's own
    /// node an instance shows among them (`Label` in `Chip/Label`). Detaching the
    /// instance first rewrites that end to the detached copy, which the delete leaves be,
    /// so the connector stays — unless an end still names a removed node after the
    /// rewrite.
    ///
    /// - Parameters:
    ///   - connectorIDs: The connectors the delete, planned before the detaches, takes.
    ///   - refIDs: The instances detached first, in order.
    ///   - removed: Every node the delete removes, descendants included.
    /// - Returns: The connectors the delete should leave.
    func connectorsKept(_ connectorIDs: [String], detaching refIDs: [String], removing removed: Set<String>) throws -> Set<String> {
        guard !refIDs.isEmpty, !connectorIDs.isEmpty else { return [] }
        let candidates = Set(connectorIDs)
        var kept: Set<String> = []
        for connector in try detachedConnectors(for: detachPlans(for: refIDs)) where candidates.contains(connector.connectorID) {
            guard case let .connection(data) = connector.after else { continue }
            let touches = [data.source.path, data.target.path].contains { path in
                path.split(separator: NodeAddress.separator).contains { removed.contains(String($0)) }
            }
            if !touches { kept.insert(connector.connectorID) }
        }
        return kept
    }

    /// What every connector end a detach renames names, mapped to its derived id: the
    /// plan's id mapping, and each instance's own path mapped to its root's.
    ///
    /// An expansion spells an instance's root `<instance path>/<component root>`
    /// (`Card/Button`, `Card/row/Item`), but a connector end names the instance by its
    /// path alone (`Card`, `Card/row`). A node is an instance root when the path before
    /// its last step differs from its parent's — the step into a new instance — and the
    /// expansion's own root always is one, its path the ref's id.
    ///
    /// - Parameters:
    ///   - expanded: The expansion, before its ids are replaced.
    ///   - refID: The ref being detached.
    ///   - idMapping: Expanded id → derived id, for every node of `expanded`.
    /// - Returns: `idMapping`, with each instance path added.
    static func endMapping(of expanded: PenNode, refID: String, idMapping: [String: String]) -> [String: String] {
        var mapping = idMapping
        mapping[refID] = idMapping[expanded.id]
        var pending: [(node: PenNode, parentPath: String?)] = expanded.kind.inlineChildren.map { ($0, instancePath(of: expanded.id)) }
        while let (node, parentPath) = pending.popLast() {
            let path = instancePath(of: node.id)
            if let path, path != parentPath, mapping[path] == nil {
                mapping[path] = idMapping[node.id]
            }
            pending.append(contentsOf: node.kind.inlineChildren.map { ($0, path) })
        }
        return mapping
    }

    /// An expanded id without its last step, or `nil` for an id with one step.
    private static func instancePath(of expandedID: String) -> String? {
        expandedID.lastIndex(of: NodeAddress.separator).map { String(expandedID[..<$0]) }
    }

    /// A connector end's path after a detach.
    ///
    /// A path names a stored node by id and steps into instances (`instance/child`). The
    /// steps from the detached ref on are the ref's expanded id spelling, which the plan's
    /// ``PlannedDetach/endMapping`` renames — the longest prefix it knows, so a node inside
    /// an instance nested in the detached one keeps the steps past that instance. Steps
    /// before the ref are kept: they reach it through instances of a component holding it.
    ///
    /// - Parameters:
    ///   - path: The end's path.
    ///   - plan: The detach.
    /// - Returns: The path naming the same node after the detach, or `path` unchanged
    ///   when it does not pass through the ref.
    static func detachedPath(_ path: String, by plan: PlannedDetach) -> String {
        let steps = path.split(separator: NodeAddress.separator, omittingEmptySubsequences: false).map(String.init)
        guard let start = steps.firstIndex(of: plan.refID) else { return path }
        let separator = String(NodeAddress.separator)
        let renamed = StructuralEditPlan(operations: [], renamedIDs: plan.endMapping)
            .renamed(steps[start...].joined(separator: separator))
        return (steps[..<start] + [renamed]).joined(separator: separator)
    }
}
