//
//  EditPlanner.swift
//  Woodcase
//

import Foundation

/// Turns what a caller wants changed into the edits that change it, or a refusal.
///
/// The one planner every writer shares. `woodcase set` and `woodcase override`, a batch
/// line, a script's `doc.set` and an editor's inspector all hand it an ``EditIntent`` and
/// an address, and get back the same ``EditPlan`` — so "the CLI and the canvas disagree
/// about what this edit means" cannot happen. It decides:
///
/// - **where the edit is stored.** A node with storage of its own is set in place; a
///   node inside a component instance is overridden on that instance, and only when the
///   caller asks for ``EditIntent/override(_:unset:)`` — a set, bind or unbind aimed there
///   is refused with ``EditRefusal/Code/setInsideInstance``, because a write there changes
///   that instance only, never the component. That is a Woodcase rule, not each caller's.
/// - **what the value becomes**: deep `common.metadata.<key>` paths folded onto the
///   object the node carries, a number written to a text property stored as its text,
///   a published parameter routed to the node it names, content an instance wrote into
///   its own slot written into that slot's fill.
/// - **whether to write it at all.** Unknown keys, values of the wrong form, numbers
///   outside a property's ``PenValueConstraint``, a `$name` naming no variable or one of
///   the wrong type, and an `x`/`y` on a node its parent's layout places are refused
///   with a stable ``EditRefusal/Code``.
///
/// Planning never mutates. The refusals are a **write** rule: a file that breaks them
/// still opens, and an ``EditOperation`` applied without planning — a three-way merge,
/// an undo, a peer's write — is applied as it is, so a document that loaded can always
/// be merged.
///
/// ```swift
/// let plan = try EditPlanner.plan(.override(["kind.fills": "#E5484D"]), at: address, in: document)
/// plan.storage     // .instanceOverride
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// ```
///
/// ## Topics
///
/// ### Planning
/// - ``plan(_:at:in:)-(_,NodeAddress,_)``
/// - ``plan(_:at:in:)-(_,ResolvedNodeAddress,_)``
///
/// ### Restructuring
/// - ``planGroup(nodeIDs:kind:in:layout:)``
/// - ``planUngroup(groupID:in:layout:)``
public enum EditPlanner {
    /// Plans an intent against the node an address names.
    ///
    /// - Parameters:
    ///   - intent: What to change.
    ///   - address: The node to change: a path, an id, or a path stepping into an
    ///     instance.
    ///   - document: The document the plan will be applied to, as it stands.
    /// - Returns: The edits, where they are stored, and what the result will say.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    public static func plan(
        _ intent: EditIntent,
        at address: NodeAddress,
        in document: EditableDocument
    ) throws(EditRefusal) -> EditPlan {
        do {
            return try planning(intent, at: address, in: document, tags: [:])
        } catch {
            throw EditRefusal(error, address: address.description, in: document)
        }
    }

    /// Plans an intent against a node an editor already holds resolved.
    ///
    /// The same plan ``plan(_:at:in:)-(_,NodeAddress,_)`` makes for the address that
    /// resolves to `target`, without resolving one.
    ///
    /// - Parameters:
    ///   - intent: What to change.
    ///   - target: The node to change.
    ///   - document: The document the plan will be applied to, as it stands.
    /// - Returns: The edits, where they are stored, and what the result will say.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    public static func plan(
        _ intent: EditIntent,
        at target: ResolvedNodeAddress,
        in document: EditableDocument
    ) throws(EditRefusal) -> EditPlan {
        do {
            return try planning(intent, at: target, written: target.address, in: document)
        } catch {
            throw EditRefusal(error, address: target.address, in: document)
        }
    }

    // MARK: - The shared core

    /// Resolves an address and plans an intent, throwing the error the document or the
    /// grammar raised rather than an ``EditRefusal``.
    ///
    /// This is the path the batch applier — and so every CLI verb — takes, because its
    /// messages and exit codes are keyed by those error types. The public entry points
    /// run exactly this and translate what it throws.
    ///
    /// - Parameters:
    ///   - intent: What to change.
    ///   - address: The node to change.
    ///   - document: The document, as it stands.
    ///   - tags: Tag name → node id, for a batch line addressing what an earlier one made.
    /// - Returns: The plan.
    /// - Throws: ``EditingError``, ``BatchError`` or ``EditRefusal``.
    static func planning(
        _ intent: EditIntent,
        at address: NodeAddress,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> EditPlan {
        // An override with nothing in it is refused before the address is looked at, as
        // it always has been: the missing payload is the mistake, wherever it was aimed.
        if case let .override(properties, unset) = intent, properties.isEmpty, unset.isEmpty {
            throw BatchError.overrideWithoutProperties(address: address.description)
        }
        let resolved = try document.resolve(address, tags: tags)
        return try planning(intent, at: resolved, written: address.description, in: document)
    }

    /// Plans an intent against a resolved target.
    ///
    /// - Parameters:
    ///   - intent: What to change.
    ///   - target: The node to change.
    ///   - written: The address as the caller wrote it, for messages.
    ///   - document: The document, as it stands.
    /// - Returns: The plan.
    /// - Throws: ``EditingError``, ``BatchError`` or ``EditRefusal``.
    static func planning(
        _ intent: EditIntent,
        at target: ResolvedNodeAddress,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        let plan = switch intent {
        case let .set(properties):
            try planSet(properties, at: target, written: written, in: document)
        case let .override(properties, unset):
            try planOverride(properties, unset: unset, at: target, written: written, in: document)
        case let .resetOverride(keys):
            try planOverride([:], unset: keys, at: target, written: written, in: document)
        case let .bind(property, variable):
            try planBind(property, to: variable, at: target, written: written, in: document)
        case let .unbind(property):
            try planUnbind(property, at: target, written: written, in: document)
        }
        // The document's own refusals — an unknown key, a component loop — are raised
        // here, before anything is written, rather than when the edits are applied, so an
        // editor learns of them at the same moment as the planner's own.
        for operation in plan.operations {
            try document.validate(operation)
        }
        return plan
    }
}
