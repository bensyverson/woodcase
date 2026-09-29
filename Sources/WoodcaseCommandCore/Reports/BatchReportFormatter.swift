//
//  BatchReportFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders what `apply` did: the terse per-line outline it prints by default, and the
/// `--json` form a later `--retry` reads back.
///
/// ```text
/// line 0  applied  Canvas/Hero  k2Bq9
/// line 1  failed   the document has changed: rev was 000... — re-read it and rebuild this line
/// line 2  cascaded discarded: the batch is atomic, and line 1 failed
/// 1 applied, 1 failed, 1 cascaded — revision aB3xQ...
/// ```
///
/// An applied line that stored something other than what it said carries its
/// ``Woodcase/WriteDivergence`` sentences indented under its own row, past the
/// `line N` gutter, so a sentence is never separated from the line it is about. A line
/// that diverged from nothing prints the single row it always did.
///
/// A `--dry-run` leads with ``DryRunOption/marker``, drops the revision from the
/// summary — it left the document where it found it — and follows the summary with the
/// findings the settled batch would introduce, in `lint`'s own line format.
///
/// Line numbers are ``BatchLineResult/line`` exactly as the applier reports it —
/// 0-based — because an atomic batch's own cascade message already says "line 1
/// failed" in that numbering; a formatter that relabeled rows 1-based would disagree
/// with the sentence sitting right beside it.
enum BatchReportFormatter {
    /// The status column's fixed width, so every row's content starts at the same place.
    private static let statusColumnWidth = 8

    /// Renders the report as the default columnar outline.
    ///
    /// - Parameter report: The report to render.
    /// - Returns: One line per operation, then a summary line, with no trailing newline.
    static func text(_ report: BatchReport) -> String {
        var lines: [String] = report.dryRun == true ? [DryRunOption.marker] : []
        lines += report.lines.flatMap(rows(for:))
        lines.append(summary(for: report))
        if let findings = report.lint, !findings.isEmpty {
            lines.append(LintFormatter.text(findings))
        }
        return lines.joined(separator: "\n")
    }

    /// Renders the report as JSON, sorted keys, so a `--retry` reads back exactly what
    /// a `--json` run wrote.
    ///
    /// - Parameter report: The report to render.
    /// - Returns: The JSON text of `report`.
    /// - Throws: Whatever `JSONEncoder` throws.
    static func json(_ report: BatchReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(report), as: UTF8.self)
    }

    // MARK: - Private

    /// One line's rows: its own, then one per divergence it reported.
    ///
    /// A line that stored exactly what it was handed reports no divergence, so this is
    /// the single row it has always been — the echo costs the common case nothing.
    private static func rows(for line: BatchLineResult) -> [String] {
        [row(for: line)] + line.divergences.map { divergenceRow($0) }
    }

    /// One line's row: `line N  <status>  <content>`, columns fixed-width regardless
    /// of the status word's length.
    private static func row(for line: BatchLineResult) -> String {
        "line \(line.line)  \(statusColumn(line.status)) \(content(for: line))"
    }

    /// A divergence's row, indented past the `line N` gutter so it reads as belonging
    /// to the row above rather than as a line of the batch.
    ///
    /// The sentence is ``Woodcase/WriteDivergence/reportLine``, so a
    /// ``Woodcase/WriteDivergence/Severity/note`` keeps its marker here too: the two
    /// tiers read the same in a batch as they do under a single verb.
    private static func divergenceRow(_ divergence: WriteDivergence) -> String {
        String(repeating: " ", count: statusColumnWidth) + divergence.reportLine
    }

    /// The status word, padded so every row's content starts at the same column.
    private static func statusColumn(_ status: BatchLineStatus) -> String {
        let word = status.rawValue
        return word + String(repeating: " ", count: max(0, statusColumnWidth - word.count))
    }

    /// What a row says after its status: where an applied line landed, or why a
    /// failed or cascaded one did not.
    private static func content(for line: BatchLineResult) -> String {
        switch line.status {
        case .applied:
            if let path = line.path {
                return line.created.first.map { "\(path)  \($0.id)" } ?? path
            }
            // A line that acts on no single node — a variable, or a `cp` whose `each`
            // made several copies — names what it made instead of where it landed.
            guard !line.created.isEmpty else { return "document" }
            return line.created
                .map { created in created.name.map { "\($0)  \(created.id)" } ?? created.id }
                .joined(separator: ", ")
        case .failed, .cascaded:
            return line.error ?? "no message"
        }
    }

    /// The final line: how many lines ended in each status, and the revision the
    /// batch left the document at.
    ///
    /// A dry run has no revision to name — it left the document where it found it — so
    /// the counts stand alone. See ``Woodcase/BatchReport/previewing(lint:)``.
    private static func summary(for report: BatchReport) -> String {
        let applied = report.count(of: .applied)
        let failed = report.count(of: .failed)
        let cascaded = report.count(of: .cascaded)
        let counts = "\(applied) applied, \(failed) failed, \(cascaded) cascaded"
        guard let revision = report.documentRevision else { return counts }
        return "\(counts) — revision \(revision)"
    }
}
