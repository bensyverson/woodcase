//
//  UndoCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Reverses the most recent recorded edits to a .pen file by replaying their inverses.
///
/// An act verb over the activity log. The walk itself is the library's —
/// ``Woodcase/ActivityUndo`` — so a caller with a log can undo an edit without a shell;
/// what lives here is the argv, the rows and the sentences.
struct Undo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write: reverse the most recent recorded edits to a .pen file.",
        discussion: """
        An act verb. Working back from the newest entry in the activity log for this \
        file, undo replays the inverse of up to N edits made by you — or by anyone, \
        with --all. It refuses rather than guesses: an edit is only reversed when the \
        file's revision is still the one that edit produced, so a later edit by \
        somebody else stops the undo and names them (exit 3).

        One step is one TRANSACTION — one command's worth of writes, however many \
        events it logged — so undoing a batch, a `cp --times 3` or a script run takes \
        one undo, and -n counts commands. --event steps one logged row at a time \
        instead, for when the row is what you mean.

        An undo is itself recorded, so a second undo reaches the edit before the one \
        the first reversed. Undo never redoes: an undo entry in the log is stepped \
        over, never replayed. It also never guesses past an edit made outside \
        woodcase: that has no inverse to replay, and undo stops at it and says when \
        it happened.

        With nothing to reverse, undo exits 1 and says why.

        --dry-run prints the rows the reversal would produce and then rolls it back, so \
        the log still holds the events it would have undone and a second run reaches the \
        same ones.

          woodcase undo design.pen --as ana
          woodcase undo design.pen -n 3 --as ana --json
          woodcase undo design.pen --event --as ana
        """
    )

    @Argument(help: "The .pen file to reverse edits in.")
    var file: PenFilePath

    @Option(
        name: [.customShort("n"), .customLong("count")],
        help: ArgumentHelp("How many transactions to reverse, newest first.", valueName: "N")
    )
    var count: Int = 1

    @Flag(name: .long, help: "Reverse edits by any identity, not only your own.")
    var all: Bool = false

    @Flag(name: .long, help: "Reverse one logged event per step, not one whole transaction.")
    var event: Bool = false

    @OptionGroup var preview: DryRunOption

    @OptionGroup var identity: IdentityOptions<Identity.Required>

    @OptionGroup var output: OutputOptions

    /// Reverses the tail of the log and prints what it reversed.
    ///
    /// - Throws: An ``ArgumentParser/ExitCode`` from the house table, after the reason
    ///   has been written to standard error.
    func run() async throws {
        let url = try file.existingFile()
        guard count >= 1 else {
            throw UndoFailures.badCount(count)
        }
        guard let name = identity.identity else {
            throw UndoFailures.missingIdentity()
        }

        let limit = count
        let allIdentities = all
        let effect = preview.effect
        let unit: UndoUnit = event ? .event : .transaction
        let wantsJSON = output.json
        let outcome = try await runReportingFailures(editing: url) {
            try await PenFileTransaction.run(at: url, identity: name, effect: effect, fonts: .shared) { document, recorder in
                do {
                    return try Self.reverseTail(
                        in: document,
                        through: recorder,
                        editing: url,
                        identity: name,
                        allIdentities: allIdentities,
                        limit: limit,
                        unit: unit,
                        effect: effect
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
        }

        OutsideWriteNote.report(outcome, json: wantsJSON)
        // A run that reversed something and then hit a conflict keeps what it reversed:
        // discarding good work in order to report a refusal helps nobody. The refusal
        // still goes to stderr, where everything that is not the answer goes.
        if let stopped = outcome.value.stopped {
            StandardError.write(stopped.message)
        }
        let report = outcome.value.report
        try print(wantsJSON ? report.json() : report.text)
    }

    /// What one undo produced: the answer, and the refusal that ended it early.
    private struct Result {
        /// The rows to print.
        let report: UndoReport

        /// Why the scan stopped before reaching `-n` steps, or `nil` if it did not.
        let stopped: CommandFailure?
    }

    /// Runs the library's walk and turns what it says into this verb's answer.
    ///
    /// - Parameters:
    ///   - document: The document the transaction opened.
    ///   - recorder: The recorder every inverse is applied through.
    ///   - url: The .pen file being undone.
    ///   - identity: The `--as` name running the undo.
    ///   - allIdentities: Whether `--all` was passed.
    ///   - limit: How many steps to reverse at most.
    ///   - unit: Whether a step is a transaction or a single event.
    ///   - effect: Whether this is a rehearsal, which is what decides whether the
    ///     findings are collected and the revision dropped.
    /// - Returns: The report, and the refusal that stopped the walk early.
    /// - Throws: A ``CommandFailure`` when *nothing* was reversed — the refusal that
    ///   blocked the walk, or the clean negative for a file with nothing to undo. The
    ///   transaction therefore writes nothing.
    private static func reverseTail(
        in document: EditableDocument,
        through recorder: ActivityRecorder,
        editing url: URL,
        identity: String,
        allIdentities: Bool,
        limit: Int,
        unit: UndoUnit,
        effect: WriteEffect
    ) throws -> Result {
        let findings = try effect.preview(of: document)
        let reversal = try ActivityUndo.reverse(
            in: document,
            through: recorder,
            editing: url,
            identity: identity,
            allIdentities: allIdentities,
            limit: limit,
            unit: unit
        )
        let stopped = reversal.stopped.flatMap {
            UndoFailures.blocked($0, editing: url, currentRevision: document.documentRevision)
        }
        guard !reversal.undone.isEmpty else {
            throw stopped ?? UndoFailures.nothingToUndo(
                editing: url, recorded: reversal.recorded, revision: document.documentRevision
            )
        }
        return try Result(
            report: UndoReport(
                file: url,
                revision: document.documentRevision,
                undone: reversal.undone,
                dryRun: effect == .dryRun,
                lint: findings?.introduced(in: document) ?? []
            ),
            stopped: stopped
        )
    }
}
