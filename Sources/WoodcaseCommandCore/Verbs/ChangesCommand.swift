//
//  ChangesCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Prints what others changed in a .pen file since your last look, with the new values,
/// and remembers where you stopped.
///
/// The agent's side of a turn: edit, let a person react in an editor, then ask this.
/// The work is the library's ``Woodcase/ChangeFeed``; here are the argv, the rows and
/// the exit codes.
struct ChangesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "changes",
        abstract: "Read: what others changed since your last look, with the new values.",
        discussion: """
        A read verb, and the one an agent asks between turns. It lists every edit \
        someone ELSE made to the file since you last ran it — one row per change: \
        time, writer, verb, then the node path and the key with its old and new value, \
        which is the `set` that would repeat it — and ends with `cursor <token>`.

          woodcase changes design.pen --as claude
          16:31:04  ben  set    Home/Hero/Title  kind.content: "Welcome" → "Welcome back"
          cursor 1a2b3c-40960

        Your last look is kept per identity and file in .woodcase/cursors/ beside the \
        activity log (a bundle's own .woodcase/), and each run moves it to the end, so the next run lists only \
        what is new. The first run lists nothing and says so: the feed starts then. \
        --peek reads without moving it; --since <cursor> starts from a cursor you kept \
        (0-0 is the whole history). --mine includes your own edits.

        --wait <seconds> blocks until someone else edits, then prints and exits 0; \
        with nothing by the deadline it exits 3, the cursor still printed. A file \
        changed outside woodcase — no record of what changed — prints a note to \
        re-read it, and that also ends a --wait.

        --as is required (or $WOODCASE_AS): the feed is yours. `woodcase activity` is \
        the plain log, every writer, newest last.
        """
    )

    @Argument(help: ArgumentHelp("The .pen file or .umbra bundle.", valueName: "file"))
    var file: PenFilePath

    /// Who is looking, which ``Identity/Looker`` says.
    @OptionGroup var identity: IdentityOptions<Identity.Looker>

    /// Selects the report's JSON instead of rows.
    @OptionGroup var output: OutputOptions

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Start from this cursor (a `cursor` line's token) instead of your last look.",
            valueName: "cursor"
        )
    )
    var since: String?

    @Flag(name: .long, help: "Read without moving your cursor.")
    var peek = false

    @Flag(name: .long, help: "Include your own edits.")
    var mine = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Block until someone else edits, or this many seconds pass (then exit 3).",
            valueName: "seconds"
        )
    )
    var wait: Int?

    /// Rejects a `--since` that is not a cursor and a `--wait` that is not a duration.
    func validate() throws {
        if let since, ActivityCursor(token: since) == nil {
            throw ValidationError(
                "--since \(since) is not a cursor: pass the token a `cursor` line printed, "
                    + "or \(ActivityCursor.start.token) for the whole history."
            )
        }
        if let wait, wait < 1 {
            throw ValidationError("--wait must be at least 1 second.")
        }
    }

    func run() async throws {
        let url = try file.existingFile()
        guard let name = identity.identity else {
            throw CommandFailure(
                message: """
                changes needs an identity: pass `--as <name>`, or set \
                $\(Identity.environmentVariable). The feed is yours — it resumes from your \
                last look and leaves out your own edits.
                """,
                exitCode: .usage
            )
        }
        let feed = ChangeFeed(file: url, identity: name, writers: mine ? .everyone : .others)
        let start: ChangeFeed.Start = since.flatMap(ActivityCursor.init(token:)).map { .cursor($0) } ?? .stored

        let report = try await runReportingFailures(editing: url) {
            let report = if let wait {
                try await feed.wait(from: start, timeout: .seconds(wait))
            } else {
                try await feed.read(from: start)
            }
            if !peek {
                try await feed.save(report)
            }
            return report
        }

        if output.json {
            try print(Self.json(report))
        } else {
            for line in ChangesFormatter.lines(report, file: file.path, writers: feed.writers) {
                print(line)
            }
        }
        if let wait, report.isEmpty {
            StandardError.write("""
            no changes by \(mine ? "anyone" : "others") within \(wait)s. Next: \
            `woodcase changes \(file.path) --wait \(wait)` to keep waiting.
            """)
            throw ExitCode.conflict
        }
    }

    /// The report as one line of JSON, keys sorted.
    private static func json(_ report: ChangeFeed.Report) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(report), as: UTF8.self)
    }
}
