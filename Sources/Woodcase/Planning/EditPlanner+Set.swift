//
//  EditPlanner+Set.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Plans a ``EditIntent/set(_:)``: in place on a node with storage of its own, as an
    /// override on the instance for a node inside one.
    ///
    /// - Parameters:
    ///   - properties: The values to write, keyed by property path.
    ///   - target: The node to write them on.
    ///   - written: The address as written, for messages.
    ///   - document: The document, as it stands.
    /// - Returns: The plan.
    /// - Throws: ``EditingError``, ``BatchError`` or ``EditRefusal``.
    static func planSet(
        _ properties: [String: AnyCodable],
        at target: ResolvedNodeAddress,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        switch target {
        case let .node(id):
            try planNodeSet(properties, on: id, written: written, in: document)
        case let .instanceDescendant(refID, key):
            try planSetAsOverride(properties, refID: refID, descendantKey: key, written: written, in: document)
        }
    }

    // MARK: - In place

    /// A set on a node that stores its own properties.
    private static func planNodeSet(
        _ properties: [String: AnyCodable],
        on id: String,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        guard let node = document.node(id: id) else {
            return EditPlan(
                operations: [.setProperties(EditOperation.SetProperties(nodeID: id, properties: properties))],
                targetID: id,
                storage: .node
            )
        }
        // A deep key — `common.metadata.woodcase.role` — is folded onto the object the node
        // already carries before the edit exists, so what is recorded, replicated and
        // undone is the ordinary whole-object write the format has always had.
        let props = try NodePropertyCodec.folding(properties, onto: node)
        try NodePropertyCodec.checkAuthored(props, on: node)
        try checkValues(
            props.keys.sorted().compactMap { path in
                NodePropertyCodec.fieldName(of: path).map { field in
                    ValueWrite(
                        key: path,
                        field: field,
                        value: NodePropertyCodec.coercing(props[path] ?? .null, at: path, on: node.kind),
                        current: try? NodePropertyCodec.value(at: path, of: node)
                    )
                }
            },
            on: node.kind,
            address: written,
            in: document
        )
        try checkPosition(
            PositionWrite(properties: props, vocabulary: .propertyPath),
            of: PlacedNode(node: id, in: document),
            address: written
        )
        return EditPlan(
            operations: [.setProperties(EditOperation.SetProperties(nodeID: id, properties: props))],
            targetID: id,
            storage: .node,
            divergences: propertyDivergences(props, on: node, in: document)
        )
    }

    // MARK: - Inside an instance

    /// A set on a node inside an instance, planned as the override it has to be.
    ///
    /// Deep keys fold onto the node as the instance shows it, then every path is
    /// translated to the raw key the `descendants` map uses, and the override is
    /// planned exactly as an ``EditIntent/override(_:unset:)`` would be — one rule
    /// for the value, whichever verb the caller reached for.
    private static func planSetAsOverride(
        _ properties: [String: AnyCodable],
        refID: String,
        descendantKey: String,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        let shown = document.patchedDefinitionNode(ofInstance: refID, descendantKey: descendantKey)
        let folded = try shown.map { try NodePropertyCodec.folding(properties, onto: $0) } ?? properties
        var plan = try planOverride(
            folded, unset: [],
            at: .instanceDescendant(refID: refID, descendantKey: descendantKey),
            written: written, in: document
        )
        let path = document.namePath(of: ResolvedNodeAddress.instanceDescendant(refID: refID, descendantKey: descendantKey))
        plan.divergences.insert(storedAsOverride(path, refID: refID, in: document), at: 0)
        return plan
    }

    /// The note a set inside an instance carries: where the write was stored.
    private static func storedAsOverride(
        _ path: String,
        refID: String,
        in document: EditableDocument
    ) -> WriteDivergence {
        let instance = document.namePath(of: refID)
        return WriteDivergence(
            kind: .storedAsOverride,
            severity: .note,
            target: path,
            requested: "a set on \(path)",
            applied: "an override on the instance \(instance)",
            note: "\(path) is inside the instance \(instance), so the set was stored as an "
                + "override there — the component's own node is unchanged"
        )
    }
}
