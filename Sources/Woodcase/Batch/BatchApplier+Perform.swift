//
//  BatchApplier+Perform.swift
//  Woodcase
//

import Foundation

extension BatchApplier {
    /// Plans, guards and applies one line, rolling the line back if any edit in it fails.
    ///
    /// A line is the unit of both rollback and logging: when `recorder` is present the
    /// edits go through it, and a line that fails half way through drops the events its
    /// earlier edits recorded, because those edits no longer exist.
    ///
    /// Almost every line is one plan, made before anything is written. A `cp` is the
    /// exception — it may make several copies, and the assignments *inside* a copy can
    /// only be resolved once that copy is in the document — so it plans as it goes; see
    /// ``performCopy(_:on:tags:recorder:undo:into:)``. The undo stack spans the whole
    /// line either way, so a `cp` that fails on its fourth copy leaves the file exactly
    /// as it found it.
    ///
    /// - Parameters:
    ///   - operation: The line to apply.
    ///   - document: The document to edit.
    ///   - tags: Tag name → node id, extended by a line that declares one.
    ///   - recorder: The transaction's recorder, or `nil` to log nothing.
    /// - Returns: What the line did: what it created, where it acted, and the edits
    ///   that undo it.
    /// - Throws: The ``EditingError`` or ``BatchError`` that refused it, with the
    ///   document restored to what it was before the line.
    static func perform(
        _ operation: BatchOperation,
        on document: EditableDocument,
        tags: inout [String: String],
        recorder: ActivityRecorder?
    ) throws -> LineOutcome {
        let checkpoint = recorder?.events.count ?? 0
        var undo: [[EditOperation]] = []
        var outcome = LineOutcome()

        do {
            switch operation {
            case let .cp(op):
                try performCopy(
                    op, on: document, tags: tags, recorder: recorder, undo: &undo, into: &outcome
                )
            default:
                let plan = try plan(operation, in: document, tags: tags)
                try apply(plan, to: document, recorder: recorder, undo: &undo, into: &outcome)
                outcome.created = plan.createdRootID.map { [createdTree(rootID: $0, in: document)] } ?? []
                outcome.path = plan.actedOnID.map { document.namePath(of: $0) }
                outcome.id = plan.actedOnID
                outcome.node = plan.actedOnID.flatMap { document.node(id: $0) }
            }
        } catch {
            unwind(undo, in: document)
            recorder?.discardEvents(after: checkpoint)
            throw error
        }

        outcome.inverse = undo.reversed().flatMap(\.self)
        if let tag = operation.declaredTag, let created = outcome.created.first {
            tags[tag] = created.id
        }
        return outcome
    }

    // MARK: - One plan

    /// Applies one plan's edits, capturing their inverses onto the line's undo stack.
    ///
    /// Rollback belongs to the *line*, not to the plan: a `cp` line is several plans,
    /// and a failure in the last of them must undo the first. So this throws and leaves
    /// the unwinding to ``perform(_:on:tags:recorder:)``, which owns the stack.
    ///
    /// - Parameters:
    ///   - plan: The translated edits to apply.
    ///   - document: The document to edit.
    ///   - recorder: The transaction's recorder, or `nil` to log nothing.
    ///   - undo: The line's undo stack, extended with one entry per edit applied.
    ///   - outcome: The line's answer, extended with the plan's edits and divergences.
    /// - Throws: ``BatchError/documentRevisionConflict(expected:actual:)`` when the plan
    ///   guards the document and it has moved, or whatever the document refuses an edit
    ///   with.
    static func apply(
        _ plan: BatchPlan,
        to document: EditableDocument,
        recorder: ActivityRecorder?,
        undo: inout [[EditOperation]],
        into outcome: inout LineOutcome
    ) throws {
        if let expected = plan.expectedDocumentRevision {
            let actual = document.documentRevision
            guard expected == actual else {
                throw BatchError.documentRevisionConflict(expected: expected, actual: actual)
            }
        }
        for (index, edit) in plan.operations.enumerated() {
            let inverse = try document.prepareInverse(of: edit)
            // The revision guard belongs before anything is written, so it
            // rides the first edit; `apply(_:expecting:)` checks then applies.
            let expecting = index == 0 ? plan.expecting : [:]
            if let recorder {
                try recorder.apply(edit, expecting: expecting)
            } else {
                try document.apply(edit, expecting: expecting)
            }
            undo.append(inverse)
        }
        outcome.operations += plan.operations
        outcome.divergences += plan.divergences
    }
}
