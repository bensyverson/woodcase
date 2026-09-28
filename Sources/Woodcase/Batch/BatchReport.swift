//
//  BatchReport.swift
//  Woodcase
//

import Foundation

/// The result of applying a batch: one line per operation, plus what the
/// document ended up as.
///
/// A report is the input to a retry as well as its output, so it round-trips
/// through JSON and keeps a line for every operation — including the ones a
/// retry did not re-run.
public struct BatchReport: Friendly {
    /// Creates a report.
    ///
    /// - Parameters:
    ///   - lines: One result per operation, in batch order.
    ///   - documentRevision: The document's revision after the batch.
    ///   - atomic: Whether the batch ran all-or-nothing.
    ///   - identity: The peer the batch was applied as.
    ///   - warnings: Non-fatal things the batch is telling the caller about, as whole
    ///     sentences. `nil` — never an empty array — when there are none.
    public init(
        lines: [BatchLineResult],
        documentRevision: String?,
        atomic: Bool = false,
        identity: PeerID? = nil,
        warnings: [String]? = nil
    ) {
        self.lines = lines
        self.documentRevision = documentRevision
        self.atomic = atomic
        self.identity = identity
        self.warnings = warnings
    }

    /// One result per operation, in batch order.
    public var lines: [BatchLineResult]

    /// The document's ``EditableDocument/documentRevision`` after the batch.
    ///
    /// Unchanged from before the batch when nothing was applied, and `nil` for a dry
    /// run — see ``previewing(lint:)``.
    public var documentRevision: String?

    /// Whether the batch ran all-or-nothing.
    public var atomic: Bool

    /// The peer the batch was applied as, or `nil` when the caller gave none.
    public var identity: PeerID?

    /// What the batch wants the caller to read but did not fail over — today, the
    /// artboards it left overlapping — or `nil` when there is nothing.
    ///
    /// Set by the caller after the batch, not by the applier: the applier knows what
    /// each line did, and a warning like this is about the document the whole batch
    /// left behind. `nil` rather than `[]` so a clean report's JSON carries no empty
    /// key, and so a report written before this key existed still decodes.
    public var warnings: [String]?

    /// `true` when the batch was rehearsed rather than applied, and `nil` when it was a
    /// real write.
    ///
    /// `nil` rather than `false` so a committed batch's JSON carries no extra key and a
    /// report written before this one existed still decodes. Set by
    /// ``previewing(lint:)``.
    public var dryRun: Bool?

    /// The lint findings the batch would introduce, or `nil` when it was a real write.
    ///
    /// Populated for a dry run only, from ``LintPreview`` over the document the whole
    /// batch settled — every line together, never one at a time, because a line that
    /// breaks the layout and a later line that repairs it must net out to nothing.
    public var lint: [LintFinding]?

    // MARK: - Reading a report

    /// This report recast as a rehearsal's answer.
    ///
    /// The revision goes, because a dry run leaves the file at the revision it already
    /// had and the one the batch *would* have produced is a token no file carries —
    /// exactly the plausible wrong answer a `rm` refuses to print a node revision for.
    /// In its place go the flag that says nothing was written and the findings the
    /// result would have.
    ///
    /// - Parameter findings: What ``LintPreview/introduced(in:)`` reported over the
    ///   settled batch.
    /// - Returns: A copy of this report, marked as a dry run.
    public func previewing(lint findings: [LintFinding]) -> BatchReport {
        var preview = self
        preview.documentRevision = nil
        preview.dryRun = true
        preview.lint = findings
        return preview
    }

    /// Whether every line applied.
    public var succeeded: Bool {
        lines.allSatisfy { $0.status == .applied }
    }

    /// The line numbers a retry would re-run: everything that failed or cascaded.
    ///
    /// Sorted, so a caller can print them as written.
    public var retryableLines: [Int] {
        lines.filter { $0.status != .applied }.map(\.line).sorted()
    }

    /// How many lines ended in each status.
    ///
    /// - Parameter status: The status to count.
    /// - Returns: The number of lines with that status.
    public func count(of status: BatchLineStatus) -> Int {
        lines.count(where: { $0.status == status })
    }

    /// Every node the batch created, outermost first, in batch order.
    public var createdNodes: [CreatedNode] {
        lines.flatMap(\.created)
    }
}
