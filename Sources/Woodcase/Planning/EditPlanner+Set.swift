//
//  EditPlanner+Set.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Plans a ``EditIntent/set(_:)``: in place on a node with storage of its own, and
    /// refused for a node inside an instance.
    ///
    /// - Parameters:
    ///   - properties: The values to write, keyed by property path.
    ///   - target: The node to write them on.
    ///   - written: The address as written, for messages.
    ///   - document: The document, as it stands.
    /// - Returns: The plan.
    /// - Throws: ``BatchError/setInsideInstance(address:instancePath:properties:)`` for a
    ///   node inside an instance; otherwise ``EditingError``, ``BatchError`` or
    ///   ``EditRefusal``.
    static func planSet(
        _ properties: [String: AnyCodable],
        at target: ResolvedNodeAddress,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        try NodePropertyCodec.checkNoStoragePaths(properties, nodeID: target.targetID)
        switch target {
        case let .node(id):
            return try planNodeSet(properties, on: id, written: written, in: document)
        case let .instanceDescendant(refID, key):
            throw setInsideInstance(properties, refID: refID, descendantKey: key, written: written, in: document)
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
        // A deep key — `codegen.role` — is folded onto the object the node
        // already carries before the edit exists, so what is recorded, replicated and
        // undone is the ordinary whole-object write the format has always had.
        // A whole `kind.effects` restates every spread: the ones its shadows name, by place.
        let restated = try NodePropertyCodec.restatingShadowSpreads(properties, on: node)
        let props = try NodePropertyCodec.folding(restated, onto: node)
        // Before the convention's own check, so a number out of range is refused as
        // outOfRange, as the `kind.` key it stands in for would be, not as a bad form.
        try checkMetadataValues(props, asWritten: properties, on: node, address: written)
        try checkStrokeDash(props, on: node, address: written)
        do {
            try NodePropertyCodec.checkAuthored(props, on: node)
        } catch {
            throw respelled(error, asWritten: properties)
        }
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

    /// The refusal of a set inside an instance, carrying the override it should have been.
    ///
    /// A write there changes this instance only, never the component, and an agent that
    /// reached for `set` meant to change the node — so the planner does not quietly store
    /// an override. The override is planned only when it is asked for by name,
    /// ``EditIntent/override(_:unset:)``, and this refusal spells out that request: deep
    /// keys folded onto the node the override patches, paths turned into the raw keys
    /// the `descendants` map uses.
    private static func setInsideInstance(
        _ properties: [String: AnyCodable],
        refID: String,
        descendantKey: String,
        written: String,
        in document: EditableDocument
    ) -> BatchError {
        let patched = document.patchedDefinitionNode(ofInstance: refID, descendantKey: descendantKey)
        // A natural path (`kind.strokeDash`) stays itself: an override stores it under its
        // raw key, which expansion reads into the node's metadata key by key.
        let natural = properties.filter { path, _ in PenMetadata.WoodcaseKey(naturalPath: path) != nil }
        let deep = properties.filter { path, _ in natural[path] == nil }
        let folded = (patched.flatMap { try? NodePropertyCodec.folding(deep, onto: $0) } ?? deep)
            .merging(natural) { _, new in new }
        return BatchError.setInsideInstance(
            address: written,
            instancePath: document.namePath(of: refID),
            properties: NodePropertyCodec.rawKeyed(folded)
        )
    }
}
