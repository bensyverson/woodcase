//
//  UndoReport.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// What `woodcase undo` answers with: one row per event it reversed, newest first,
/// and the revision the file now holds.
///
/// ```text
/// set  ana  2026-08-29T18:41:07.123Z  Canvas/Title
/// add  ana  2026-08-29T18:40:55.900Z  Canvas/Badge
/// revision 6c1f0a72b48d3e91
/// ```
///
/// A row is one *event*, not one operation: an event's inverse may be several
/// operations, and the thing the reader undid is the event. The columns are the verb,
/// the identity, the time and the name path — the free-text path last, so that
/// splitting a row on whitespace still yields the three fields an agent branches on
/// even when a node's name contains spaces.
///
/// The trailing `revision` line is the token a following command passes back, per
/// `project/agents/cli-design.md`: anything an agent might reason about and then
/// mutate hands back a revision. A `--dry-run` prints the same rows between
/// ``DryRunOption/marker`` and the findings the reversal would introduce, and no
/// revision line — the file is still at the one it had, and the one the reversal would
/// have made names nothing.
struct UndoReport: Friendly {
    /// One reversed event.
    struct Row: Friendly {
        /// Describes one reversed event.
        ///
        /// - Parameter event: The event whose inverse was replayed.
        init(_ event: ActivityEvent) {
            identity = event.identity
            nodes = event.nodes
            op = event.op.rawValue
            paths = event.paths
            time = ActivityEvent.wireTime(event.time)
        }

        /// Who made the edit that was reversed.
        let identity: String

        /// The node ids the reversed edit touched, most specific first.
        let nodes: [String]

        /// The short verb the reversed edit read as — `add`, `set`, `mv`, `rm`.
        let op: String

        /// The name paths of ``nodes``, in the same order.
        let paths: [String]

        /// When the reversed edit was made, in the activity log's own wire format, so
        /// a row and its log line read the same.
        let time: String

        /// The row as one line of the text form.
        var line: String {
            "\(op)  \(identity)  \(time)  \(paths.first ?? Self.noTarget)"
        }

        /// The path column for an event that changed the document rather than a node.
        static let noTarget = "-"
    }

    /// Describes a finished undo.
    ///
    /// - Parameters:
    ///   - file: The .pen file that was undone.
    ///   - revision: The document revision the undo left behind.
    ///   - undone: The events reversed, in the order they were reversed — newest first.
    ///   - dryRun: Whether this was a rehearsal. A rehearsal drops the revision — the
    ///     file is still at the one it had, and the log still holds the events this
    ///     would have reversed — and gains the marker and the findings. See
    ///     ``DryRunOption``.
    ///   - lint: The findings the undo would introduce, from ``Woodcase/LintPreview``.
    ///     Only a dry run has any.
    init(
        file: URL,
        revision: String,
        undone: [ActivityEvent],
        dryRun: Bool = false,
        lint: [LintFinding] = []
    ) {
        self.file = ActivityEvent.canonicalPath(for: file)
        self.revision = dryRun ? nil : revision
        self.undone = undone.map(Row.init)
        self.dryRun = dryRun ? true : nil
        self.lint = dryRun ? lint : nil
    }

    /// The .pen file that was undone, in the same canonical form the log records.
    let file: String

    /// The document revision the undo left behind, or `nil` for a dry run — which made
    /// none, and leaves the file at the one it already had.
    let revision: String?

    /// The events reversed, newest first.
    let undone: [Row]

    /// `true` when nothing was written, `nil` when something was.
    let dryRun: Bool?

    /// The lint findings the undo would introduce, or `nil` for a real undo.
    let lint: [LintFinding]?

    /// The default output: one row per reversed event, then the revision.
    ///
    /// A dry run leads with ``DryRunOption/marker``, prints no revision — it made none —
    /// and follows with the findings it would introduce.
    var text: String {
        var lines: [String] = dryRun == true ? [DryRunOption.marker] : []
        lines += undone.map(\.line)
        if let revision {
            lines.append("revision \(revision)")
        }
        if let lint, !lint.isEmpty {
            lines.append(LintFormatter.text(lint))
        }
        return lines.joined(separator: "\n")
    }

    /// The `--json` output.
    ///
    /// - Returns: The report as JSON, with sorted keys and unescaped slashes so paths
    ///   stay readable and the bytes are the same every run.
    /// - Throws: Whatever `JSONEncoder` throws.
    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }
}
