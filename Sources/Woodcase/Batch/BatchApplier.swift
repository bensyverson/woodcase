//
//  BatchApplier.swift
//  Woodcase
//

import Foundation

/// Applies a batch of ``BatchOperation`` to an ``EditableDocument``.
///
/// This is the core behind `woodcase apply`, and — with a one-element array —
/// behind every mutating verb, so a `set` behaves identically alone and in a batch.
///
/// A batch **applies what it can**. Each line is planned, revision-checked and
/// applied on its own; a line that fails changes nothing and does not stop the
/// batch, and a line that could only have depended on a failed one is reported
/// as ``BatchLineStatus/cascaded`` rather than attempted. The alternative —
/// rolling everything back — punishes a typo on line 11 with the loss of lines
/// 1 through 10.
///
/// ```swift
/// let operations = try BatchOperation.decodeJSONL(String(contentsOf: url))
/// let report = BatchApplier.apply(operations, to: document, identity: PeerID(rawValue: "ben"))
/// for line in report.lines where line.status != .applied {
///     print("line \(line.line): \(line.error ?? "")")
/// }
/// ```
///
/// ## Topics
///
/// ### Applying
/// - ``apply(_:to:atomic:identity:recorder:)``
/// - ``retry(_:report:to:atomic:identity:recorder:)``
/// - ``applyOne(_:to:recorder:log:file:)``
///
/// ### Guarding
/// - ``checkGuards(_:in:log:file:)``
///
/// ### Reporting
/// - ``createdTree(rootID:in:)``
///
/// ### Placement
/// - ``RootOverlap/margin``
public enum BatchApplier {
    // MARK: - Applying

    /// Applies a batch in order, and reports what became of each line.
    ///
    /// Addresses resolve through ``EditableDocument/resolve(_:tags:)-(NodeAddress,_)``
    /// against the document *as it stands at that line*, so a line can address
    /// what an earlier line created — by `@tag`, or by the path it now has.
    ///
    /// > Important: This does **not** check the batch's ``BatchGuard``s. A guard is an
    /// entry gate that refuses the whole transaction, and this reports rather than
    /// throws, so the two cannot be the same call. Call
    /// ``checkGuards(_:in:log:file:)`` first, as the first statement of the transaction
    /// body; a caller that does not is running the batch unguarded.
    ///
    /// In `atomic` mode the batch runs against a deep copy first and is replayed
    /// onto `document` only if every line applies; the first failure discards
    /// everything, leaving `document` untouched and every other line reported as
    /// ``BatchLineStatus/cascaded``. Replaying the *translated* edits, rather
    /// than re-running the batch, is what keeps the ids in the report equal to
    /// the ids the document ends up with.
    ///
    /// - Parameters:
    ///   - operations: The batch, in file order.
    ///   - document: The document to edit.
    ///   - atomic: Whether to discard everything on the first failure.
    ///   - identity: The peer this batch is applied as, recorded on the report.
    ///   - recorder: The transaction's ``ActivityRecorder``, when the batch should be
    ///     logged. Every edit that reaches `document` then goes through it, so a batch
    ///     logs exactly what the same edits log applied one at a time. A line that
    ///     rolls back leaves no events behind, and a `nil` recorder logs nothing.
    /// - Returns: One ``BatchLineResult`` per operation.
    public static func apply(
        _ operations: [BatchOperation],
        to document: EditableDocument,
        atomic: Bool = false,
        identity: PeerID? = nil,
        recorder: ActivityRecorder? = nil
    ) -> BatchReport {
        run(
            operations, lines: Array(operations.indices), carrying: [:], previous: nil,
            to: document, atomic: atomic, identity: identity, recorder: recorder
        )
    }

    /// Re-runs only the lines of a previous batch that failed or cascaded.
    ///
    /// A retry is a patch, not a resend: lines that already applied are left
    /// alone and keep their previous result, and the tags they declared are
    /// still resolvable, so a repaired line can still say `@hero`. Pass the
    /// operations with the broken lines fixed; the array must be the same
    /// length and order as the one that produced `report`, because
    /// ``BatchLineResult/line`` indexes it.
    ///
    /// - Parameters:
    ///   - operations: The batch, with failed lines repaired.
    ///   - report: The report from the previous run.
    ///   - document: The document to edit, as it stands now.
    ///   - atomic: Whether to discard everything on the first failure.
    ///   - identity: The peer this batch is applied as, recorded on the report.
    ///   - recorder: The transaction's ``ActivityRecorder``, when the retry should be
    ///     logged. Only the lines actually re-run are recorded; the ones carried over
    ///     were logged by the run that applied them.
    /// - Returns: A report covering every line: the re-run ones freshly, the
    ///   rest carried over.
    public static func retry(
        _ operations: [BatchOperation],
        report: BatchReport,
        to document: EditableDocument,
        atomic: Bool = false,
        identity: PeerID? = nil,
        recorder: ActivityRecorder? = nil
    ) -> BatchReport {
        var tags: [String: String] = [:]
        for line in report.lines where line.status == .applied {
            guard operations.indices.contains(line.line) else { continue }
            if let tag = operations[line.line].declaredTag, let created = line.created.first {
                tags[tag] = created.id
            }
        }
        return run(
            operations,
            lines: report.retryableLines.filter { operations.indices.contains($0) },
            carrying: tags, previous: report,
            to: document, atomic: atomic, identity: identity, recorder: recorder
        )
    }

    // MARK: - The run

    /// One line's effect on the document, before it becomes a ``BatchLineResult``.
    struct LineOutcome {
        /// The edits the line translated into, for an atomic replay.
        var operations: [EditOperation] = []
        /// The edits that undo the line, in application order.
        var inverse: [EditOperation] = []
        /// The subtrees the line created, in the order it made them.
        var created: [CreatedNode] = []
        /// The full name path of the node the line acted on, or `nil` for a line that
        /// acts on no single node.
        var path: String?
        /// The id of the node the line acted on.
        var id: String?
        /// That node as the line left it, or `nil` when the line removed it.
        var node: PenNode?
        /// The ways the result differs from the line as it was written.
        var divergences: [WriteDivergence] = []
    }

    private static func run(
        _ operations: [BatchOperation],
        lines: [Int],
        carrying seedTags: [String: String],
        previous: BatchReport?,
        to document: EditableDocument,
        atomic: Bool,
        identity: PeerID?,
        recorder: ActivityRecorder?
    ) -> BatchReport {
        // Atomic runs edit a deep copy, so a failure leaves the real document alone.
        let stage = atomic ? EditableDocument(from: document.materialize()) : document
        // The recorder belongs to the real document. An atomic batch's staged run
        // happens on a copy the recorder knows nothing about, so it records nothing
        // there; the replay onto the real document is what goes through the recorder.
        let lineRecorder = atomic ? nil : recorder
        var tags = seedTags
        var poison = BatchPoison()
        var results: [Int: BatchLineResult] = [:]
        var staged: [(line: Int, operations: [EditOperation])] = []
        var culprit: Int?

        for line in lines {
            let operation = operations[line]

            if let reason = poison.cascadeReason(for: operation, in: stage, tags: tags) {
                results[line] = BatchLineResult(line: line, status: .cascaded, error: reason)
                poison.absorb(operation, in: stage, tags: tags)
                continue
            }

            do {
                let outcome = try perform(
                    operation, on: stage, tags: &tags, recorder: lineRecorder
                )
                results[line] = BatchLineResult(
                    line: line, status: .applied,
                    created: outcome.created, path: outcome.path, inverse: outcome.inverse,
                    id: outcome.id, node: outcome.node, divergences: outcome.divergences
                )
                staged.append((line, outcome.operations))
            } catch {
                results[line] = BatchLineResult(
                    line: line, status: .failed,
                    error: BatchErrorMessage.describe(error, in: stage),
                    isRevisionConflict: isRevisionConflict(error)
                )
                poison.absorb(operation, in: stage, tags: tags)
                if atomic {
                    culprit = line
                    break
                }
            }
        }

        if atomic {
            if let culprit {
                for line in lines where line != culprit {
                    results[line] = BatchLineResult(
                        line: line, status: .cascaded,
                        error: "discarded: the batch is atomic, and line \(culprit) failed"
                    )
                }
            } else {
                replay(staged, onto: document, results: &results, recorder: recorder)
            }
        }

        return BatchReport(
            lines: operations.indices.map { index in
                results[index]
                    ?? previous?.lines.first { $0.line == index }
                    ?? BatchLineResult(line: index, status: .cascaded, error: "not attempted")
            },
            documentRevision: document.documentRevision,
            atomic: atomic,
            identity: identity
        )
    }

    /// Replays an atomic batch's translated edits onto the real document.
    ///
    /// The staged run already proved these edits apply to a document identical
    /// to this one, so a failure here is not a user error; it is rolled back so
    /// the atomic promise holds either way. This is also the only place an atomic
    /// batch touches the recorder: the staged run happened on a copy.
    private static func replay(
        _ staged: [(line: Int, operations: [EditOperation])],
        onto document: EditableDocument,
        results: inout [Int: BatchLineResult],
        recorder: ActivityRecorder?
    ) {
        let checkpoint = recorder?.events.count ?? 0
        var undo: [[EditOperation]] = []
        for entry in staged {
            for edit in entry.operations {
                do {
                    let inverse = try document.prepareInverse(of: edit)
                    if let recorder {
                        try recorder.apply(edit)
                    } else {
                        try document.apply(edit)
                    }
                    undo.append(inverse)
                } catch {
                    unwind(undo, in: document)
                    recorder?.discardEvents(after: checkpoint)
                    let message = BatchErrorMessage.describe(error, in: document)
                    let conflict = isRevisionConflict(error)
                    for other in staged {
                        results[other.line] = BatchLineResult(
                            line: other.line,
                            status: other.line == entry.line ? .failed : .cascaded,
                            error: other.line == entry.line
                                ? message
                                : "discarded: the batch is atomic, and line \(entry.line) failed",
                            isRevisionConflict: other.line == entry.line ? conflict : false
                        )
                    }
                    return
                }
            }
        }
    }

    /// Whether a failure was a stale revision, as opposed to any other refusal.
    ///
    /// This is what ``BatchLineResult/isRevisionConflict`` reports: the one
    /// distinction a caller mapping the report onto an exit code needs without
    /// parsing the message's prose.
    private static func isRevisionConflict(_ error: any Error) -> Bool {
        if let editing = error as? EditingError, case .revisionConflict = editing { return true }
        if let batch = error as? BatchError, case .documentRevisionConflict = batch { return true }
        return false
    }

    /// Applies captured inverses in reverse, restoring the document.
    ///
    /// This goes straight to the document, never through a recorder: an unwind is the
    /// undoing of edits that are being dropped, not an edit of its own, and logging it
    /// would leave the log describing work the file never kept.
    static func unwind(_ undo: [[EditOperation]], in document: EditableDocument) {
        for group in undo.reversed() {
            for edit in group {
                try? document.apply(edit)
            }
        }
    }
}
