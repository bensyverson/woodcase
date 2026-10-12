//
//  EditPlanner+Override.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Plans an ``EditIntent/override(_:unset:)``: a write into an instance's
    /// `descendants` map, or onto its root overrides.
    ///
    /// - Parameters:
    ///   - properties: The overrides to write, by property path or raw key.
    ///   - unset: The keys whose override is removed.
    ///   - target: The instance, or a node inside one.
    ///   - written: The address as written, for messages.
    ///   - document: The document, as it stands.
    /// - Returns: The plan, stored on the instance.
    /// - Throws: ``BatchError/overrideWithoutProperties(address:)``,
    ///   ``BatchError/overrideOutsideInstance(address:path:)``, ``EditingError`` or
    ///   ``EditRefusal``.
    static func planOverride(
        _ properties: [String: AnyCodable],
        unset: [String],
        at target: ResolvedNodeAddress,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        guard !properties.isEmpty || !unset.isEmpty else {
            throw BatchError.overrideWithoutProperties(address: written)
        }
        let refID: String
        let descendantKey: String?
        switch target {
        case let .instanceDescendant(instance, key):
            (refID, descendantKey) = (instance, key)
        case let .node(id):
            // The instance's own address writes the component root's properties as this
            // instance shows them — `rootOverrides`, which the format spells as the ref
            // node's own non-reserved keys. Anything that is not an instance is a node
            // with storage of its own, and belongs to `set`.
            guard case .ref = document.node(id: id)?.kind else {
                throw BatchError.overrideOutsideInstance(address: written, path: document.namePath(of: target))
            }
            (refID, descendantKey) = (id, nil)
        }
        // A key the component publishes as a parameter is routed to the node that
        // parameter names before the vocabularies are reconciled, so `label=Hi` and
        // `Body/Title content=Hi` produce the same descendants entry.
        let definition = descendantKey.map {
            document.patchedDefinitionNode(ofInstance: refID, descendantKey: $0)
        } ?? document.componentRoot(ofInstance: refID)
        let routed = try routing(properties, at: descendantKey, of: definition, in: document)
        let unsetKeys = unset.map { NodePropertyCodec.rawKey(for: $0) }

        var operations: [EditOperation] = []
        var divergences: [WriteDivergence] = routed.notes
        for group in routed.groups(keepingTarget: !unsetKeys.isEmpty) {
            // The two vocabularies meet here. The caller may write either —
            // `kind.content` or `content` — and the `descendants` map keys only the raw
            // one, so the write is translated rather than refused; the values then take
            // the same number-to-string rule a `set` gives them, judged against the node
            // inside the component the override will patch.
            let requested = NodePropertyCodec.rawKeyed(group.props)
            let patched = group.descendantKey == descendantKey
                ? definition
                : group.descendantKey.flatMap {
                    document.patchedDefinitionNode(ofInstance: refID, descendantKey: $0)
                }
            let overrides = patched
                .map { NodePropertyCodec.coercingOverrides(requested, on: $0.kind) } ?? requested
            try NodePropertyCodec.checkAuthoredOverride(
                overrides, on: patched, refID: refID, descendantKey: group.descendantKey
            )
            try checkOverrideValues(
                overrides, on: patched, refID: refID, descendantKey: group.descendantKey,
                written: written, in: document
            )
            let keys = group.descendantKey == descendantKey ? unsetKeys : []
            let edit: EditOperation = group.descendantKey.map { key in
                .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: refID, descendantID: key, properties: overrides, unset: keys
                ))
            } ?? .overrideRoot(EditOperation.OverrideRoot(
                refNodeID: refID, properties: overrides, unset: keys
            ))
            // Content the instance wrote into its own slot takes no `descendants` key —
            // Pen drops one — so the write goes into the fill that holds it.
            if case let .overrideDescendant(override) = edit,
               let rewrite = try document.slotFillRewrite(of: override)
            {
                operations.append(.overrideDescendant(rewrite.operation))
                divergences.append(slotFillNote(override, landingIn: rewrite))
            } else {
                operations.append(edit)
            }
            divergences += overrideDivergences(
                overrides, requested: requested,
                descendantKey: group.descendantKey, on: refID, in: document
            )
        }
        return EditPlan(
            operations: operations,
            targetID: refID,
            storage: .instanceOverride,
            divergences: divergences
        )
    }

    /// Holds an override's values to the same constraints, bindings and position rule a
    /// set is held to, judged against the node the override patches.
    ///
    /// A value equal to what the instance already shows is let through, as a set's is.
    private static func checkOverrideValues(
        _ overrides: [String: AnyCodable],
        on patched: PenNode?,
        refID: String,
        descendantKey: String?,
        written: String,
        in document: EditableDocument
    ) throws {
        guard let patched else { return }
        // A `type` key replaces the whole node, which is decoded whole and judged as the
        // node it becomes rather than key by key.
        guard overrides[PenDescendantOverride.typeKey] == nil else { return }
        let shown = try? NodePropertyCodec.encode(patched)
        let current: [String: AnyCodable] = if case let .dictionary(stored)? = shown { stored } else { [:] }
        try checkValues(
            overrides.keys.sorted().map { key in
                ValueWrite(
                    key: key,
                    field: NodePropertyCodec.fieldName(forRawKey: key),
                    value: overrides[key] ?? .null,
                    current: current[key]
                )
            },
            on: patched.kind,
            address: written,
            in: document
        )
        guard let descendantKey else { return }
        try checkPosition(
            PositionWrite(properties: overrides, vocabulary: .rawKey),
            of: PlacedNode(descendant: descendantKey, ofInstance: refID, in: document),
            address: written
        )
    }
}
