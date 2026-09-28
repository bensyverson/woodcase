//
//  ApplyCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Applies a batch of edits to a `.pen` file, and reports what became of each line.
///
/// A batch **applies what it can**: a bad line fails without stopping the rest, and a
/// line that could only have depended on a failed one is reported as cascaded rather
/// than attempted. `--atomic` opts into all-or-nothing instead. See
/// ``BatchOperation/grammar`` for the wire format — this verb's `--help` prints it
/// verbatim, so there is nothing to restate here.
///
/// ```bash
/// woodcase apply design.pen -F ops.jsonl --as ana
/// woodcase apply design.pen -F ops.jsonl --atomic
/// woodcase apply design.pen -F ops.jsonl --json > report.json
/// woodcase apply design.pen -F ops.jsonl --retry report.json --as ana
/// echo '{"op":"set","target":"Card/Title","props":{"kind.content":"Hi"}}' \
///   | woodcase apply design.pen -F -
/// ```
///
/// The exit code says how the batch went as a whole, on top of the per-line report:
/// 0 when every line applied, 3 when a failed line was a stale revision, 1 for every
/// other mix of failed or cascaded lines. A malformed batch file — one that will not
/// even decode — never opens the document at all, and is 2 (usage), naming the line.
///
/// A ``BatchGuard`` is checked before any of that. Every line's guards are asserted at
/// transaction entry by ``Woodcase/BatchApplier/checkGuards(_:in:log:file:)``, so a
/// moved premise refuses the whole batch with exit 3 and no report at all — nothing was
/// applied to report on.
///
/// `--guard` puts the same premise on argv, which is where a caller who composed the
/// batch from one read wants it: written bare it pins the whole document, because that
/// is what a batch acts on, and `<node>=<rev>` pins that node's subtree exactly as the
/// line-level form does. Argv's pins are asserted first, then every line's.
///
/// ```bash
/// woodcase apply design.pen -F ops.jsonl --guard 9c1b04e6f2a71d38
/// woodcase apply design.pen -F ops.jsonl --guard Dashboard=4f2a1b0c9d8e7f60
/// ```
struct Apply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Write: apply a batch of edits to a .pen file.",
        discussion: """
        \(BatchOperation.grammar)

        A bare --guard pins the whole document, which is what a batch acts on;
        --guard <node>=<rev> pins that node's subtree. See "Guards" above.

        EXAMPLE
          woodcase apply design.pen -F ops.jsonl --as ana
          woodcase apply design.pen -F ops.jsonl --guard 9c1b04e6f2a71d38
          woodcase apply design.pen -F ops.jsonl --retry report.json --as ana
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp(
            "The batch: one operation per JSON line. `-` reads standard input.",
            valueName: "file"
        )
    )
    var opsPath: String

    @Flag(name: .long, help: "Discard every edit in the batch if any line fails.")
    var atomic: Bool = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "A previous --json report. Only its failed and cascaded lines are re-run.",
            valueName: "path"
        )
    )
    var retry: String?

    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    func run() async throws {
        let url = try file.existingFile()
        let pins = try premise.guards()
        let effect = preview.effect
        let outcome = try await runReportingFailures(
            editing: url
        ) { () async throws -> PenFileTransaction.Outcome<BatchReport> in
            let operations = try Apply.readOperations(from: opsPath)
            let previousReport = try retry.map(Apply.readReport(from:))
            return try await PenFileTransaction.run(
                at: url, identity: identity.identity, effect: effect,
                fonts: .shared
            ) { document, recorder in
                let log = ActivityLogLocation.log(for: url)
                do {
                    // A batch acts on the whole file, so a bare `--guard` pins the
                    // document; argv's premises are asserted before the lines' own.
                    try BatchApplier.checkGuards(
                        pins, pinning: .document, of: "apply",
                        in: document, log: log, file: url
                    )
                    try BatchApplier.checkGuards(
                        Apply.guardedLines(of: operations, retrying: previousReport),
                        in: document,
                        log: log,
                        file: url
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
                let overlapping = RootOverlapWarnings.baseline(in: document)
                // One snapshot for the whole batch, and one comparison after it: a line
                // that breaks the layout and a later line that repairs it net out to
                // nothing, which is what "the batch settles before it lints" means.
                let findings = try effect.preview(of: document)
                var report: BatchReport = if let previousReport {
                    BatchApplier.retry(
                        operations, report: previousReport, to: document,
                        atomic: atomic, recorder: recorder
                    )
                } else {
                    BatchApplier.apply(operations, to: document, atomic: atomic, recorder: recorder)
                }
                let warnings = RootOverlapWarnings.lines(since: overlapping, in: document, file: url.path)
                report.warnings = warnings.isEmpty ? nil : warnings
                guard let findings else { return report }
                return try report.previewing(lint: findings.introduced(in: document))
            }
        }

        let report = outcome.value
        OutsideWriteNote.report(outcome, json: output.json)
        try print(output.json ? BatchReportFormatter.json(report) : BatchReportFormatter.text(report))
        RootOverlapWarnings.report(report.warnings ?? [])

        let code = Apply.exitCode(for: report)
        guard code != .success else { return }
        throw code
    }

    /// The lines whose guards the transaction asserts at its door.
    ///
    /// Every line of an ordinary run. For a `--retry` only the lines that will actually
    /// be re-run: a line that already applied moved its own subtree when it did, so
    /// re-asserting its premise would refuse the repair the retry exists to make.
    ///
    /// - Parameters:
    ///   - operations: The batch, in file order.
    ///   - report: The previous run's report, for a retry.
    /// - Returns: The operations to check guards on.
    static func guardedLines(
        of operations: [BatchOperation],
        retrying report: BatchReport?
    ) -> [BatchOperation] {
        guard let report else { return operations }
        return report.retryableLines
            .filter { operations.indices.contains($0) }
            .map { operations[$0] }
    }

    // MARK: - Reading input

    /// Decodes the batch from a file, or from standard input when `path` is `-`.
    ///
    /// - Parameter path: A file path, or `-` for standard input.
    /// - Returns: The batch, in file order.
    /// - Throws: ``CommandFailure`` if the path cannot be read;
    ///   ``BatchError/malformedLine(line:reason:)`` naming the line that would not decode.
    static func readOperations(from path: String) throws -> [BatchOperation] {
        try BatchOperation.decodeJSONL(readText(from: path))
    }

    /// Decodes a previous `--json` report, for `--retry`.
    ///
    /// - Parameter path: The report file's path.
    /// - Returns: The decoded report.
    /// - Throws: ``CommandFailure`` if the path cannot be read or does not decode as a
    ///   ``BatchReport``.
    static func readReport(from path: String) throws -> BatchReport {
        let data = try readData(from: path)
        do {
            return try JSONDecoder().decode(BatchReport.self, from: data)
        } catch {
            throw CommandFailure(
                message: "Cannot read \(path) as a batch report: \(error).",
                exitCode: .usage
            )
        }
    }

    /// The exit code a finished batch ends the process with.
    ///
    /// - Parameter report: The report the batch produced.
    /// - Returns: ``ExitCode/success`` if every line applied; ``ExitCode/conflict`` if
    ///   a failed line was a stale revision; ``ExitCode/cleanNegative`` for every other
    ///   mix of failed or cascaded lines.
    static func exitCode(for report: BatchReport) -> ExitCode {
        guard !report.succeeded else { return .success }
        let conflicted = report.lines.contains { $0.status == .failed && $0.isRevisionConflict }
        return conflicted ? .conflict : .cleanNegative
    }

    // MARK: - Private

    private static func readText(from path: String) throws -> String {
        try String(decoding: InputFile.data(at: path), as: UTF8.self)
    }

    private static func readData(from path: String) throws -> Data {
        try InputFile.data(at: path)
    }
}
