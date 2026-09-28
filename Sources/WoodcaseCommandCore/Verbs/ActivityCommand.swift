//
//  ActivityCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Shows the activity log: one row per applied edit, or the events themselves as JSON.
///
/// ```text
/// $ woodcase activity demo.pen -n 5
/// 16:31:04 | ana | set      | layout-vertical/first
/// 16:31:05 | ana | theme    | -
/// ```
///
/// The file and `--as` narrow the feed. The file may be written as the first argument,
/// where every other verb takes it, or as `--file`; the two mean the same thing, and
/// naming two different files is a usage error. Unlike a writing verb, `--as` here is a
/// *filter* on whose edits to show, not an attribution for an edit this command makes
/// — `activity` never writes. `--follow` keeps the process running, printing new
/// events as they are appended, until it is interrupted or the process that launched
/// it goes away.
///
/// With `--file` it reads that file's own project log; with no file, the log of the
/// project the working directory is in — so `woodcase activity` in a checkout is that
/// checkout's history.
///
/// An activity log with nothing in it yet is not a failure, and neither is a `.woodcase`
/// no verb has created yet: the command prints nothing and exits 0. A log directory that
/// exists but is not a readable directory is a different thing — the environment is
/// broken, not merely quiet — so that exits 5 and names the path.
struct Activity: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read: the activity log of edits applied to .pen files.",
        discussion: """
        Prints the most recent events, newest last, as one line each — time, identity, \
        verb, path — or every matching event as JSON (--json), one event per line in \
        the same form the log stores, so it round-trips.

        A read verb: it opens no .pen file at all, only the log. The log is the \
        project's: .woodcase/activity.jsonl beside the nearest .git, and with no file \
        it is the project the working directory is in. Naming a .pen file — as the \
        first argument, or with --file, which mean the same thing — narrows to that \
        file and reads its own project log, whether or not the file still exists; \
        --as narrows to one writer, a filter here rather than the attribution it is on \
        a verb that edits; --follow keeps printing as new events are appended, until \
        interrupted.

          woodcase activity design.pen --as ana -n 20

        An empty or not-yet-created log prints nothing and exits 0 — that is not a \
        failure. A log directory that exists but is not a readable directory is: it \
        names the environment, not the feed, so it exits 5.
        """
    )

    /// Narrows the feed to one writer's events, which is what ``Identity/Filter`` says.
    @OptionGroup var identity: IdentityOptions<Identity.Filter>

    /// Selects JSONL instead of the row outline.
    @OptionGroup var output: OutputOptions

    /// The .pen file to narrow to, written where every other verb takes it.
    ///
    /// `activity` opens no .pen file, which is why the filter started life as `--file`
    /// alone; but every other verb's first argument is the file, and a caller reaching
    /// for `woodcase activity design.pen` is not making a mistake. Both spellings mean
    /// the same thing, and ``resolvedFile`` is the one place that is decided.
    @Argument(help: ArgumentHelp(
        "Show only events for this .pen file. The file need not still exist.",
        valueName: "file"
    ))
    var positionalFile: PenFilePath?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Show only events for this .pen file — the same as writing it as the argument.",
            valueName: "path"
        )
    )
    var file: PenFilePath?

    @Option(
        name: [.customShort("n"), .long],
        help: ArgumentHelp("How many of the most recent events to show.", valueName: "count")
    )
    var count = 50

    @Flag(name: .long, help: "Keep printing new events as they are appended, until interrupted.")
    var follow = false

    /// Rejects a negative `-n`, and two different files where there can only be one.
    func validate() throws {
        guard count >= 0 else {
            throw ValidationError("-n/--count must not be negative.")
        }
        if let positionalFile, let file, positionalFile.path != file.path {
            throw ValidationError(
                "\(positionalFile.path) and --file \(file.path) name different files, and "
                    + "activity reads one feed. Give the file once, as the argument."
            )
        }
    }

    /// The .pen file to narrow the feed to, from whichever spelling was used.
    ///
    /// The two spellings are equivalent, so either alone is the answer and both
    /// together have already been checked to agree by ``validate()``.
    private var resolvedFile: PenFilePath? {
        positionalFile ?? file
    }

    func run() async throws {
        // Before the first byte of output: a launcher may exit the moment it sees it.
        let parentWatch = ParentProcessWatch()
        try await runReportingFailures {
            let fileURL = resolvedFile?.url
            // With a file, that file's project log; without one, this directory's.
            let log = fileURL.map { ActivityLogLocation.log(for: $0) }
                ?? ActivityLogLocation.log(
                    inDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                )
            try Self.checkHomeAccessible(log)
            let reader = ActivityReader(log: log)
            let who = identity.identity

            do {
                let page = try reader.read(file: fileURL, identity: who)
                try Self.printEvents(Array(page.events.suffix(count)), json: output.json)

                guard follow else { return }
                try await Self.printFollowing(
                    reader.follow(from: page.nextOffset, file: fileURL, identity: who),
                    json: output.json,
                    until: parentWatch
                )
            } catch let error as PenFileError {
                throw Self.environmentFailure(for: error, log: log)
            }
        }
    }

    // MARK: - Private

    /// Prints events as they are appended, until the feed ends or nobody is left to
    /// read them.
    ///
    /// `--follow` is the one verb with no ending of its own, so it needs a second
    /// reason to stop besides a signal. The launcher going away is that reason: a
    /// follower whose reader is gone is printing into nothing, and left alone it
    /// outlives every process that knew about it. See ``ParentProcessWatch``.
    ///
    /// - Parameters:
    ///   - events: The feed of newly appended events.
    ///   - json: Whether to print each event's own JSON line instead of a row.
    ///   - parentWatch: The launcher to outlive, recorded before anything was printed.
    /// - Throws: Whatever ``printEvents(_:json:)`` throws.
    private static func printFollowing(
        _ events: ActivityReader.Follow, json: Bool, until parentWatch: ParentProcessWatch
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in events {
                    try printEvents([event], json: json)
                }
            }
            group.addTask {
                await parentWatch.waitUntilOrphaned()
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Confirms the log's directory, if it exists, is one this process can read.
    ///
    /// A log with no events yet is a normal, empty feed — ``ActivityReader`` already
    /// reports that as an empty page rather than an error — and so is a directory no
    /// verb has created yet: a project's first `activity` is not a broken environment.
    /// What *is* broken is a directory that exists and is not a directory, or one this
    /// process cannot read; those name the path and exit 5.
    ///
    /// - Parameter log: The log whose ``ActivityLog/home`` to check.
    /// - Throws: ``CommandFailure`` with ``ExitCode/environment``.
    private static func checkHomeAccessible(_ log: ActivityLog) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: log.home.path, isDirectory: &isDirectory) else {
            return
        }
        guard isDirectory.boolValue else {
            throw CommandFailure(
                message: "\(log.home.path) is not a directory, so no log can live there. "
                    + remedy(for: log),
                exitCode: .environment
            )
        }
        guard FileManager.default.isReadableFile(atPath: log.home.path) else {
            throw CommandFailure(
                message: "\(log.home.path) is not readable. "
                    + "Next: `chmod +rx \(log.home.path)`, " + remedy(for: log),
                exitCode: .environment
            )
        }
    }

    /// Wraps a failure reading the log as an environment error, since `activity` edits
    /// no .pen file of its own — whatever went wrong is about where the log lives.
    ///
    /// - Parameters:
    ///   - error: The failure reading or opening the log.
    ///   - log: The log that could not be read.
    /// - Returns: A ``CommandFailure`` with ``ExitCode/environment``.
    private static func environmentFailure(for error: PenFileError, log: ActivityLog) -> CommandFailure {
        CommandFailure(
            message: "Cannot read the activity log: \(error). " + remedy(for: log),
            exitCode: .environment
        )
    }

    /// The sentence that says what to do about a log that cannot be read.
    ///
    /// Only an ``ActivityLog/Origin/environmentOverride`` log is `$WOODCASE_HOME`'s
    /// doing; for the other two the variable is the *escape*, so it is offered rather
    /// than blamed.
    ///
    /// - Parameter log: The log in question.
    /// - Returns: One sentence naming the next command.
    private static func remedy(for log: ActivityLog) -> String {
        switch log.origin {
        case .environmentOverride:
            "Check $\(ActivityLog.homeEnvironmentVariable), which points at \(log.home.path)."
        case .repository, .directory:
            "Remove it, or set $\(ActivityLog.homeEnvironmentVariable) to a directory you can read."
        }
    }

    /// Prints events in the requested form, flushing standard output afterward so a
    /// `--follow`ing reader sees each line as soon as it is written rather than once
    /// a buffer happens to fill.
    ///
    /// - Parameters:
    ///   - events: The events to print, in the order to print them.
    ///   - json: Whether to print each event's own JSON line instead of a row.
    /// - Throws: Whatever ``ActivityEvent/jsonLine()`` throws.
    private static func printEvents(_ events: [ActivityEvent], json: Bool) throws {
        for event in events {
            if json {
                try print(String(decoding: event.jsonLine(), as: UTF8.self))
            } else {
                print(ActivityRowFormatter.row(for: event))
            }
        }
        if !events.isEmpty {
            fflush(stdout)
        }
    }
}
