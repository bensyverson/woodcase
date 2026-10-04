//
//  BatchApplier+Perform.swift
//  Woodcase
//

import Foundation

extension BatchApplier {
    /// Plans, guards and applies one line, rolling the line back if any edit in it fails.
    ///
    /// A line is the unit of both rollback and logging. Every edit is submitted to
    /// `session`, and a line that fails half way through rolls the session back to where
    /// the line began — the document, the ledger and the events its earlier edits
    /// recorded together, because those edits no longer exist.
    ///
    /// Almost every line is one plan, made before anything is written. A `cp` is the
    /// exception — it may make several copies, and the assignments *inside* a copy can
    /// only be resolved once that copy is in the document — so it plans as it goes; see
    /// ``performCopy(_:on:tags:undo:into:)``. The checkpoint spans the whole
    /// line either way, so a `cp` that fails on its fourth copy leaves the file exactly
    /// as it found it.
    ///
    /// - Parameters:
    ///   - operation: The line to apply.
    ///   - session: The session the line's edits are submitted to.
    ///   - tags: Tag name → node id, extended by a line that declares one.
    /// - Returns: What the line did: what it created, where it acted, and the edits
    ///   that undo it.
    /// - Throws: The ``EditingError`` or ``BatchError`` that refused it, with the
    ///   session restored to what it was before the line.
    static func perform(
        _ operation: BatchOperation,
        on session: DocumentSession,
        tags: inout [String: String]
    ) throws -> LineOutcome {
        let document = session.document
        let checkpoint = session.checkpoint()
        var undo: [[EditOperation]] = []
        var outcome = LineOutcome()

        do {
            switch operation {
            case let .cp(op):
                try performCopy(op, on: session, tags: tags, undo: &undo, into: &outcome)
            default:
                let plan = try plan(operation, in: document, tags: tags)
                try apply(plan, to: session, undo: &undo, into: &outcome)
                outcome.created = plan.createdRootID.map { [createdTree(rootID: $0, in: document)] } ?? []
                outcome.path = plan.actedOnID.map { document.namePath(of: $0) }
                outcome.id = plan.actedOnID
                outcome.node = plan.actedOnID.flatMap { document.node(id: $0) }
            }
        } catch {
            try session.rollback(to: checkpoint)
            throw error
        }

        outcome.inverse = undo.reversed().flatMap(\.self)
        if let tag = operation.declaredTag, let created = outcome.created.first {
            tags[tag] = created.id
        }
        return outcome
    }

    // MARK: - One plan

    /// Submits one plan's edits to the session as one change, capturing their inverses
    /// onto the line's undo stack.
    ///
    /// Rollback belongs to the *line*, not to the plan: a `cp` line is several plans,
    /// and a failure in the last of them must undo the first. So this throws and leaves
    /// the rolling back to ``perform(_:on:tags:)``, which holds the checkpoint. The
    /// plan's own edits land together or not at all, as any session change does.
    ///
    /// - Parameters:
    ///   - plan: The translated edits to apply.
    ///   - session: The session to submit them to.
    ///   - undo: The line's undo stack, extended with one entry per edit applied: the
    ///     session's granular inverse, as the log records it.
    ///   - outcome: The line's answer, extended with the plan's edits and divergences.
    /// - Throws: ``BatchError/documentRevisionConflict(expected:actual:)`` when the plan
    ///   guards the document and it has moved, or whatever the session refuses the
    ///   edits with.
    static func apply(
        _ plan: BatchPlan,
        to session: DocumentSession,
        undo: inout [[EditOperation]],
        into outcome: inout LineOutcome
    ) throws {
        if let expected = plan.expectedDocumentRevision {
            let actual = session.document.documentRevision
            guard expected == actual else {
                throw BatchError.documentRevisionConflict(expected: expected, actual: actual)
            }
        }
        let change = try session.submit(.local(LocalEdit(operations: plan.operations, expecting: plan.expecting)))
        undo += change.applied.map { $0.inverse.map(\.operation) }
        outcome.operations += plan.operations
        outcome.divergences += plan.divergences
    }
}
