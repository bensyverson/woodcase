//
//  BatchApplier+Plan.swift
//  Woodcase
//

import Foundation

extension BatchApplier {
    /// Resolves one batch line against the document and translates it into edits.
    ///
    /// Nothing here mutates, so a line that cannot be planned fails before the
    /// document has changed at all.
    ///
    /// - Parameters:
    ///   - operation: The line to plan.
    ///   - document: The document it will run against.
    ///   - tags: Tag name → node id, for the tags earlier lines declared.
    /// - Returns: The translated plan.
    /// - Throws: ``EditingError`` from address resolution, or ``BatchError``
    ///   when the grammar was used in a way the document cannot honour.
    static func plan(
        _ operation: BatchOperation,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        switch operation {
        case let .set(op): try planSet(op, in: document, tags: tags)
        case let .add(op): try planAdd(op, in: document, tags: tags)
        case let .replace(op): try planReplace(op, in: document, tags: tags)
        case let .cp(op): try planCopy(op, in: document, tags: tags)
        case let .mv(op): try planMove(op, in: document, tags: tags)
        case let .rm(op): try planRemove(op, in: document, tags: tags)
        case let .override(op): try planOverride(op, in: document, tags: tags)
        case let .variable(op): planVariable(op, in: document)
        case let .themeAxis(op): planThemeAxis(op, in: document)
        case let .importOp(op): planImport(op, in: document)
        }
    }

    // MARK: - Node operations

    private static func planSet(
        _ op: BatchOperation.SetOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        let resolved = try document.resolve(op.target, tags: tags)
        guard case let .node(id) = resolved else {
            throw BatchError.setInsideInstance(
                address: op.target.description,
                instancePath: document.namePath(of: resolved.targetID)
            )
        }
        // A deep key — `common.metadata._role` — is folded onto the object the node
        // already carries before the edit exists, so what is recorded, replicated and
        // undone is the ordinary whole-object write the format has always had.
        let props = try document.node(id: id).map { try NodePropertyCodec.folding(op.props, onto: $0) }
            ?? op.props
        if let node = document.node(id: id) {
            try NodePropertyCodec.checkAuthored(props, on: node)
        }
        return BatchPlan(
            operations: [.setProperties(EditOperation.SetProperties(nodeID: id, properties: props))],
            expecting: expecting(op.rev, on: id),
            actedOnID: id,
            divergences: document.node(id: id)
                .map { propertyDivergences(props, on: $0, in: document) } ?? []
        )
    }

    private static func planMove(
        _ op: BatchOperation.MoveOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        let id = try nodeID(op.target, in: document, tags: tags)
        let parentID = try op.parent.map { try containerID($0, in: document, tags: tags) }
        return BatchPlan(
            operations: [.moveNode(EditOperation.MoveNode(nodeID: id, newParentID: parentID, index: op.at))],
            expecting: expecting(op.rev, on: id),
            actedOnID: id
        )
    }

    private static func planRemove(
        _ op: BatchOperation.RemoveOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        let id = try nodeID(op.target, in: document, tags: tags)
        // Detaching first is what makes the delete safe; without it the document
        // refuses a component that still has instances, and says so.
        let detached = op.detach ? document.instanceIDs(ofComponent: id) : []
        let detaches: [EditOperation] = detached.map {
            .detachRef(EditOperation.DetachRef(refNodeID: $0))
        }
        return BatchPlan(
            operations: detaches + [.deleteNode(EditOperation.DeleteNode(nodeID: id))],
            expecting: expecting(op.rev, on: id),
            actedOnID: id,
            divergences: [detachment(of: detached, removing: id, in: document)].compactMap(\.self)
        )
    }

    private static func planOverride(
        _ op: BatchOperation.OverrideOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        guard !op.props.isEmpty || !op.unset.isEmpty else {
            throw BatchError.overrideWithoutProperties(address: op.target.description)
        }
        let resolved = try document.resolve(op.target, tags: tags)
        let refID: String
        let descendantKey: String?
        switch resolved {
        case let .instanceDescendant(instance, key):
            (refID, descendantKey) = (instance, key)
        case let .node(id):
            // The instance's own address writes the component root's properties as this
            // instance shows them — `rootOverrides`, which the format spells as the ref
            // node's own non-reserved keys. Anything that is not an instance is a node
            // with storage of its own, and belongs to `set`.
            guard case .ref = document.node(id: id)?.kind else {
                throw BatchError.overrideOutsideInstance(
                    address: op.target.description,
                    path: document.namePath(of: resolved)
                )
            }
            (refID, descendantKey) = (id, nil)
        }
        // A key the component publishes as a parameter is routed to the node that
        // parameter names before the vocabularies are reconciled, so `label=Hi` and
        // `Body/Title content=Hi` produce the same descendants entry.
        let definition = descendantKey.map {
            document.patchedDefinitionNode(ofInstance: refID, descendantKey: $0)
        } ?? document.componentRoot(ofInstance: refID)
        let routed = try routing(
            op.props, at: descendantKey, of: definition, in: document
        )
        let unset = op.unset.map { NodePropertyCodec.rawKey(for: $0) }

        var operations: [EditOperation] = []
        var divergences: [WriteDivergence] = routed.notes
        for group in routed.groups(keepingTarget: !unset.isEmpty) {
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
            let properties = patched
                .map { NodePropertyCodec.coercingOverrides(requested, on: $0.kind) } ?? requested
            try NodePropertyCodec.checkAuthoredOverride(
                properties, on: patched, refID: refID, descendantKey: group.descendantKey
            )
            let keys = group.descendantKey == descendantKey ? unset : []
            let edit: EditOperation = group.descendantKey.map { key in
                .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: refID, descendantID: key, properties: properties, unset: keys
                ))
            } ?? .overrideRoot(EditOperation.OverrideRoot(
                refNodeID: refID, properties: properties, unset: keys
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
                properties, requested: requested,
                descendantKey: group.descendantKey, on: refID, in: document
            )
        }
        return BatchPlan(
            operations: operations,
            expecting: expecting(op.rev, on: refID),
            actedOnID: refID,
            divergences: divergences
        )
    }

    // MARK: - Document operations

    /// A `var` line: register whatever theme the value pins, then write the variable.
    ///
    /// A themed value names `axis=option` pairs, and until this registered them a batch
    /// could leave a document whose variables are conditioned on a `mode` its `themes`
    /// table does not have — a state `vars set --theme` cannot produce and nothing can
    /// select. The rule is that verb's, shared through
    /// ``ThemeAxisRegistrar``: an axis the document lacks is created, an option an axis
    /// lacks is appended.
    private static func planVariable(
        _ op: BatchOperation.VariableOp,
        in document: EditableDocument
    ) -> BatchPlan {
        let registrations = ThemeAxisRegistrar.registrations(for: pins(of: op.value), in: document)
        let exists = document.variables?[op.name] != nil
        return BatchPlan(
            operations: registrations.map(\.edit) + [
                exists
                    ? .updateVariable(EditOperation.UpdateVariable(name: op.name, variable: op.value))
                    : .addVariable(EditOperation.AddVariable(name: op.name, variable: op.value)),
            ],
            divergences: [themedVariable(op, registering: registrations)].compactMap(\.self)
        )
    }

    /// The options a variable's value pins, keyed by axis, in the order its variants
    /// name them.
    private static func pins(of variable: PenVariable) -> [String: [String]] {
        guard case let .themed(variants) = variable.value else { return [:] }
        var pins: [String: [String]] = [:]
        for variant in variants {
            for (axis, option) in (variant.theme ?? [:]).sorted(by: { $0.key < $1.key }) {
                pins[axis, default: []].append(option)
            }
        }
        return pins
    }

    private static func planThemeAxis(
        _ op: BatchOperation.ThemeAxisOp,
        in document: EditableDocument
    ) -> BatchPlan {
        let exists = document.themes?[op.name] != nil
        return BatchPlan(operations: [
            exists
                ? .updateThemeAxis(EditOperation.UpdateThemeAxis(name: op.name, options: op.options))
                : .addThemeAxis(EditOperation.AddThemeAxis(name: op.name, options: op.options)),
        ])
    }

    private static func planImport(
        _ op: BatchOperation.ImportOp,
        in document: EditableDocument
    ) -> BatchPlan {
        let exists = document.imports?[op.alias] != nil
        return BatchPlan(operations: [
            exists
                ? .updateImport(EditOperation.UpdateImport(alias: op.alias, path: op.path))
                : .addImport(EditOperation.AddImport(alias: op.alias, path: op.path)),
        ])
    }

    // MARK: - Shared helpers

    /// The id an address names, refusing an address that lands inside an instance.
    ///
    /// A child the instance *injected* into a slot gets its own refusal: it is not a
    /// node the component defines but one entry in a `children` list, so the remedy is
    /// to write that list again rather than to override a property.
    static func nodeID(
        _ address: NodeAddress,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> String {
        let resolved = try document.resolve(address, tags: tags)
        guard case let .node(id) = resolved else {
            if case let .instanceDescendant(refID, key) = resolved,
               let slot = document.injectionPoint(ofInstance: refID, descendantKey: key)
            {
                throw BatchError.structureInsideSlot(address: address.description, slotPath: slot)
            }
            throw BatchError.setInsideInstance(
                address: address.description,
                instancePath: document.namePath(of: resolved.targetID)
            )
        }
        return id
    }

    /// The id of a node used as a parent, with the message a parent deserves.
    static func containerID(
        _ address: NodeAddress,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> String {
        let resolved = try document.resolve(address, tags: tags)
        guard case let .node(id) = resolved else {
            throw BatchError.parentInsideInstance(
                address: address.description,
                instancePath: document.namePath(of: resolved.targetID)
            )
        }
        return id
    }

    /// The revision map for a line that guards one node.
    static func expecting(_ rev: String?, on nodeID: String) -> [String: String] {
        guard let rev else { return [:] }
        return [nodeID: rev]
    }
}
