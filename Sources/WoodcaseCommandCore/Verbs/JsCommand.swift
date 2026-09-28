//
//  JsCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase
import WoodcaseScripting

/// Runs a JavaScript program against a `.pen` file, inside one transaction.
///
/// This is where control flow lives. `apply` is the multi-edit transaction that needs no
/// program and `find` the query that needs no script; `js` is read, decide and write in
/// one pass, which no batch can express — a script measures what it just made, and
/// throws rather than commit if the measurement is wrong.
///
/// ```bash
/// woodcase js design.pen -F rows.js --as ana
/// woodcase js design.pen -F helpers.js -F rows.js --dry-run
/// echo 'doc.lint().length' | woodcase js design.pen -F -
/// ```
///
/// It sits exactly where ``Apply`` sits: one
/// ``Woodcase/PenFileTransaction/run(at:identity:log:timeout:effect:fonts:isolation:_:)``,
/// argv guards asserted at the door before a line of script runs, then the work, then
/// the transaction's own encode-and-compare. **Nothing is written until the script ends
/// without an uncaught error** — a throw, a refusal or the watchdog leaves the file byte
/// for byte what it was and the activity log with nothing in it. The script is the
/// policy: a `try` around a write carries on past it, an uncaught error rolls the whole
/// run back.
///
/// ## What it prints
///
/// stdout is the transcript, as it happens: one row per write — the path, the id, and
/// `(+N)` for the descendants a creating verb made, with divergences indented under it —
/// and the `console.log` lines where the script printed them, then `result` and
/// `document`. stderr carries `console.warn`, `console.error`, the run's warnings and
/// the refusal. `--json` prints none of that live and one object at the end, built from
/// the same ``ScriptRunReport``.
///
/// ## Exit codes
///
/// An uncaught error is 1 — the check ran and the answer is no, and the file is
/// untouched. A source that will not parse is 2, naming the source, the line and the
/// column. A stale guard, a held lock and the timeout are 3. An unreadable `.pen` file,
/// or an unreadable `-F` script, is 4. An unusable activity log is 5.
struct Js: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "js",
        abstract: "Write: run a JavaScript program over the document, in one transaction.",
        discussion: """
        The program gets `doc`, whose members mirror the editing verbs one for one — \
        set, add, replace, cp, mv, rm, override, tree, get, lint, schema, vars, themes, \
        imports — and `console`. Reads see settled layout, so a script may measure what it just \
        made and throw rather than commit. Nothing is written until the script ends \
        without an uncaught error.

        Nothing persists between runs and nothing is auto-loaded: durable code is a \
        file, and `-F helpers.js -F run.js` evaluates the helpers first in the same \
        context.

        Scripts run to completion in one pass: there is no event loop, so setTimeout, \
        fetch, require, import and top-level await all refuse.

        `woodcase help js` is the whole contract: the transaction rules, four worked \
        scripts, the TypeScript declaration of `doc`, and the sentences a refusal throws.

        EXAMPLE
          woodcase js design.pen -F rows.js --as ana
          woodcase js design.pen -F helpers.js -F rows.js --dry-run
          echo 'doc.lint().length' | woodcase js design.pen -F -

        EXIT CODES
          1  an uncaught error; the file is untouched
          2  a source that will not parse, named with its line and column
          3  a stale --guard, a held lock, or the --timeout
          4  the .pen file or a -F script could not be read
        """
    )

    /// How long a script may run before its budget is spent.
    static let defaultTimeout: Double = 30

    /// What an error reports a script read from standard input as.
    static let standardInputName = "<stdin>"

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Option(
        name: .customShort("F"),
        parsing: .singleValue,
        help: ArgumentHelp(
            "A JavaScript source. Repeatable: the files are evaluated in order in one "
                + "context, so a helpers file precedes the run that uses it. `-` reads "
                + "standard input.",
            valueName: "file"
        )
    )
    var scriptPaths: [String] = []

    @Option(
        name: .long,
        help: ArgumentHelp(
            "How many seconds the script may run before the run is ended with exit 3.",
            valueName: "seconds"
        )
    )
    var timeout: Double = Js.defaultTimeout

    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Opens the file, runs the script inside one transaction, and reports what it did.
    func run() async throws {
        let url = try file.existingFile()
        let sources = try scriptSources()
        let budget = try scriptBudget()
        let pins = try premise.guards()
        let effect = preview.effect

        try await runReportingFailures(editing: url) {
            do {
                let outcome = try await PenFileTransaction.run(
                    at: url, identity: identity.identity, effect: effect,
                    fonts: .shared
                ) { document, recorder in
                    try act(
                        on: document, recorder: recorder, at: url,
                        pins: pins, effect: effect, sources: sources, budget: budget
                    )
                }
                try report(outcome)
            } catch let rolledBack as RolledBack {
                try report(rolledBack, editing: url)
            }
        }
    }

    // MARK: - The run

    /// What the transaction's body hands back: the run, and the one thing only the body
    /// could see.
    private struct Body {
        /// What the host answered with, root overlaps and all — the host takes the
        /// before-and-after itself, so this verb never diffs the document twice.
        let run: ScriptRun

        /// The findings a rehearsal would introduce.
        let lint: [LintFinding]
    }

    /// A run that ended in an error, thrown so the transaction commits nothing.
    ///
    /// The failure has to travel *out* of the body as a throw — that is what makes the
    /// file untouched — and the report has to survive it, so it rides along.
    private struct RolledBack: Error {
        /// What the host answered with, error and all.
        let run: ScriptRun
    }

    /// Asserts the guards and runs the script against the open document.
    ///
    /// - Parameters:
    ///   - document: The open document.
    ///   - recorder: The transaction's recorder, so every write is logged as its verb
    ///     would log it.
    ///   - url: The .pen file, for the guard conflict's "who moved it" clause.
    ///   - pins: The argv guards.
    ///   - effect: Whether this is a rehearsal.
    ///   - sources: The scripts, in order.
    ///   - budget: How long the script may run.
    /// - Returns: The run and what the body alone could see.
    /// - Throws: ``CommandFailure`` for a refused guard, ``RolledBack`` for a run that
    ///   ended in an error, and whatever the linter throws.
    private func act(
        on document: EditableDocument,
        recorder: ActivityRecorder,
        at url: URL,
        pins: [BatchGuard],
        effect: WriteEffect,
        sources: [ScriptSource],
        budget: Duration
    ) throws -> Body {
        do {
            // A script acts on the whole file, as a batch does, so a bare `--guard` pins
            // the document. Asserted before the first line runs: a moved premise means
            // the script would be composing against something that is no longer there.
            try BatchApplier.checkGuards(
                pins, pinning: .document, of: "js",
                in: document, log: ActivityLogLocation.log(for: url), file: url
            )
        } catch {
            throw CommandFailure.describing(error, in: document, editing: url)
        }
        if preview.dryRun, !output.json {
            print(DryRunOption.marker)
        }

        let findings = try effect.preview(of: document)

        let watchdog = ScriptWatchdog(timeout: budget)
        watchdog.start()
        let run = ScriptHost.run(
            sources,
            over: document,
            timeout: budget,
            remedy: .command(file: file.path),
            recorder: recorder,
            sink: transcriptSink()
        )
        watchdog.cancel()

        guard run.error == nil else { throw RolledBack(run: run) }
        return try Body(
            run: run,
            lint: findings.map { try $0.introduced(in: document) } ?? []
        )
    }

    /// The live transcript, or `nil` under `--json`.
    ///
    /// `--json` answers with one object and nothing else, so there is nothing to stream:
    /// a line of prose in front of the object would break the pipe that reads it, and the
    /// same events come back on ``WoodcaseScripting/ScriptRun/events`` at the end.
    private func transcriptSink() -> ((ScriptRun.Event) -> Void)? {
        guard !output.json else { return nil }
        return { event in
            let transcript = ScriptRunFormatter.transcript(of: ScriptRunReport.Event(event))
            for line in transcript.stdout {
                print(line)
            }
            for line in transcript.stderr {
                StandardError.write(line)
            }
        }
    }

    // MARK: - Reporting

    /// Prints what a finished run did.
    ///
    /// - Parameter outcome: The transaction's outcome.
    /// - Throws: Whatever the JSON encoder throws.
    private func report(_ outcome: PenFileTransaction.Outcome<Body>) throws {
        let report = ScriptRunReport(
            run: outcome.value.run,
            commit: Js.commit(of: outcome.commit, host: outcome.value.run.commit),
            lint: outcome.value.lint,
            dryRun: preview.dryRun
        )
        OutsideWriteNote.report(outcome, json: output.json)
        try print(rendered(report))
        reportWarnings(of: report)
    }

    /// Prints what a run that ended in an error did, and exits with its house code.
    ///
    /// - Parameters:
    ///   - rolledBack: The abandoned run.
    ///   - url: The .pen file, for the sentence that says it is unchanged.
    /// - Throws: The ``ArgumentParser/ExitCode`` for the failure, always.
    private func report(_ rolledBack: RolledBack, editing url: URL) throws -> Never {
        let report = ScriptRunReport(
            run: rolledBack.run,
            commit: .rolledBack,
            dryRun: preview.dryRun
        )
        if output.json {
            try print(ScriptRunFormatter.json(report))
        }
        if let error = rolledBack.run.error, !output.json {
            for line in ScriptRunFormatter.failure(error, file: url.path) {
                StandardError.write(line)
            }
        }
        reportWarnings(of: report)
        throw rolledBack.run.error.map(Js.exitCode(for:)) ?? ExitCode.cleanNegative
    }

    /// Writes the run's warnings to standard error, unless the transcript already did.
    ///
    /// The live transcript prints each warning as the host records it, which is every run
    /// but a `--json` one: there the sink is off, so the same lines are written here from
    /// the report the object was built from. Either way each line is printed exactly once.
    ///
    /// - Parameter report: The finished run.
    private func reportWarnings(of report: ScriptRunReport) {
        guard output.json else { return }
        RootOverlapWarnings.report(report.warnings ?? [])
    }

    /// The whole of standard output for a finished run, in whichever form was asked for.
    private func rendered(_ report: ScriptRunReport) throws -> String {
        guard !output.json else { return try ScriptRunFormatter.json(report) }
        var lines = ScriptRunFormatter.tail(of: report)
        if let findings = report.lint, !findings.isEmpty {
            lines.append(LintFormatter.text(findings))
        }
        return lines.joined(separator: "\n")
    }

    /// How the run ended for the file, the transaction's answer mapped over the host's.
    ///
    /// The host answers for the *script*; the transaction knows the two things it
    /// cannot. A rehearsal is ``WoodcaseScripting/ScriptRun/Commit/previewed``, a
    /// decision made before the script started; and a script that wrote and then wrote
    /// back is ``WoodcaseScripting/ScriptRun/Commit/unchanged``, because the document
    /// encoded to the bytes it was handed — which the host cannot see, never having
    /// encoded anything.
    ///
    /// - Parameters:
    ///   - outcome: How the transaction ended.
    ///   - host: How the host said the script ended.
    /// - Returns: The commit to report.
    static func commit(
        of outcome: PenFileTransaction.Commit,
        host: ScriptRun.Commit
    ) -> ScriptRun.Commit {
        switch outcome {
        case .previewed: .previewed
        case .unchanged: .unchanged
        case .wrote: host
        }
    }

    /// The house exit code a failed run ends the process with.
    ///
    /// Everything that is not one of the three named families is the clean negative:
    /// the script ran, the answer is no, and the file is untouched.
    ///
    /// - Parameter error: Why the run ended.
    /// - Returns: The code to exit with.
    static func exitCode(for error: ScriptError) -> ExitCode {
        switch error.code {
        case ScriptErrorCode.syntaxError: .usage
        case ScriptErrorCode.timeout: .conflict
        case ScriptErrorCode.sourceUnreadable: .targetFailure
        default: .cleanNegative
        }
    }

    // MARK: - Reading the invocation

    /// The scripts to evaluate, in the order `-F` named them.
    ///
    /// A path becomes a ``WoodcaseScripting/ScriptSource/file(_:)``, so an error reports
    /// that file's own line rather than a line in a concatenation; `-` is read here and
    /// becomes a text source named ``standardInputName``.
    ///
    /// - Returns: The sources, in order.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` when no script was given, or
    ///   when standard input was named twice.
    private func scriptSources() throws -> [ScriptSource] {
        guard !scriptPaths.isEmpty else {
            throw CommandFailure(
                message: "js needs a script: pass one with -F <file>, or -F - to read it from "
                    + "standard input. `woodcase js --help` carries a worked example, and "
                    + "`woodcase find \(file.path) '<predicate>'` is the read-only sibling.",
                exitCode: .usage
            )
        }
        var sources: [ScriptSource] = []
        var readStandardInput = false
        for path in scriptPaths {
            guard path == InputFile.standardInput else {
                sources.append(.file(URL(fileURLWithPath: (path as NSString).expandingTildeInPath)))
                continue
            }
            guard !readStandardInput else {
                throw CommandFailure(
                    message: "-F - reads standard input, and standard input can only be read "
                        + "once. Put the rest in files: -F helpers.js -F - evaluates the "
                        + "helpers first, in the same context.",
                    exitCode: .usage
                )
            }
            readStandardInput = true
            try sources.append(.text(
                String(decoding: InputFile.data(at: path), as: UTF8.self),
                name: Js.standardInputName
            ))
        }
        return sources
    }

    /// How long the script may run.
    ///
    /// - Returns: The budget as a `Duration`.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` for anything that is not a
    ///   positive number of seconds — a budget of zero would refuse every script before
    ///   its first line, which is never what a caller meant.
    private func scriptBudget() throws -> Duration {
        guard timeout.isFinite, timeout > 0 else {
            throw CommandFailure(
                message: "--timeout takes a number of seconds greater than zero, and was given "
                    + "\(timeout). The default is \(Int(Js.defaultTimeout)) s.",
                exitCode: .usage
            )
        }
        return .seconds(timeout)
    }
}
