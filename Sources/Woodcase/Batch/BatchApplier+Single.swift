//
//  BatchApplier+Single.swift
//  Woodcase
//

import Foundation

public extension BatchApplier {
    /// Applies exactly one operation, throwing what it refuses.
    ///
    /// ``apply(_:to:atomic:identity:recorder:)`` *reports* a refusal, because a batch
    /// has later lines to get on with and a caller who needs to know which of them
    /// ran. One operation has neither: there is nothing to carry on with, and the
    /// caller is a single command whose whole answer is "it worked" or "here is why
    /// it did not".
    ///
    /// So this is the door a single-verb caller uses. The failure arrives as the
    /// ``EditingError`` or ``BatchError`` the document actually raised, which is what
    /// lets a CLI map it to an exit code by *type* — a stale revision is a conflict,
    /// an unknown property is a usage error — rather than by reading a sentence.
    /// Everything else is identical to a one-line batch: the same planning, the same
    /// revision guard, the same rollback if one edit of a multi-edit line fails, and
    /// the same events through the recorder.
    ///
    /// ```swift
    /// let result = try BatchApplier.applyOne(
    ///     .set(BatchOperation.SetOp(target: address, props: properties)),
    ///     to: document, recorder: recorder
    /// )
    /// print(result.path ?? "")
    /// ```
    ///
    /// Any ``BatchGuard`` on the operation is checked first, before the plan is even
    /// made. A single verb's one line *is* the whole transaction, so the moment this is
    /// called is transaction entry — which is what a guard's "unchanged by anyone else
    /// since my read" is measured against. A verb that calls this more than once
    /// (`cp --times`) carries its guards on the first call only, exactly as it carries
    /// its `rev`: the second copy runs against the document the first one produced.
    ///
    /// - Parameters:
    ///   - operation: The operation to apply.
    ///   - document: The document to edit.
    ///   - recorder: The transaction's ``ActivityRecorder``, when the edit should be
    ///     logged. `nil` logs nothing.
    ///   - log: The activity log, so a failed guard can name who wrote in between.
    ///   - file: The .pen file being edited, which is what that log is filtered by.
    /// - Returns: The applied line's result — what it created, where it acted, and the
    ///   operations that undo it.
    /// - Throws: The ``EditingError`` or ``BatchError`` that refused it. A `@tag` in
    ///   the operation resolves against nothing, because no earlier line exists.
    @discardableResult
    static func applyOne(
        _ operation: BatchOperation,
        to document: EditableDocument,
        recorder: ActivityRecorder? = nil,
        log: ActivityLog? = nil,
        file: URL? = nil
    ) throws -> BatchLineResult {
        try checkGuards([operation], in: document, log: log, file: file)
        var tags: [String: String] = [:]
        let outcome = try perform(operation, on: document, tags: &tags, recorder: recorder)
        return BatchLineResult(
            line: 0,
            status: .applied,
            created: outcome.created,
            path: outcome.path,
            inverse: outcome.inverse,
            id: outcome.id,
            node: outcome.node,
            divergences: outcome.divergences
        )
    }
}
