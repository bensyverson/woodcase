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
    ///   when the grammar was used in a way the document cannot honor.
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

    /// A `set` line: the public planner's ``EditIntent/set(_:)``, guarded by the line's
    /// `rev` on whichever node the plan stores into — the instance, for a node inside one.
    private static func planSet(
        _ op: BatchOperation.SetOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        try BatchPlan(
            EditPlanner.planning(.set(op.props), at: op.target, in: document, tags: tags),
            rev: op.rev
        )
    }

    /// An `mv` line: the move, and — where the new parent does not lay the node out — its
    /// fill sizes kept at the size they were drawn at, as
    /// ``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)`` plans them. The document is laid
    /// out only for a node with a fill size.
    private static func planMove(
        _ op: BatchOperation.MoveOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        let id = try nodeID(op.target, in: document, tags: tags)
        let parentID = try op.parent.map { try containerID($0, in: document, tags: tags) }
        let kept = EditPlanner.keptSizes(movingNode: id, into: parentID, in: document) {
            PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
        }
        return BatchPlan(
            operations: [.moveNode(EditOperation.MoveNode(nodeID: id, newParentID: parentID, index: op.at))] + kept,
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

    /// An `override` line: the public planner's ``EditIntent/override(_:unset:)``.
    private static func planOverride(
        _ op: BatchOperation.OverrideOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        try BatchPlan(
            EditPlanner.planning(.override(op.props, unset: op.unset), at: op.target, in: document, tags: tags),
            rev: op.rev
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
