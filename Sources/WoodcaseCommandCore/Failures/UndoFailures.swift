//
//  UndoFailures.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Every sentence `woodcase undo` says when it will not do what it was asked, in one
/// place so that each one names the thing, says what happened, and says the next
/// command (`project/agents/cli-design.md`).
enum UndoFailures {
    /// The refusal for a step that will not be worked past.
    ///
    /// - Parameters:
    ///   - step: The step the scan stopped on.
    ///   - url: The .pen file being undone.
    ///   - currentRevision: The document's revision right now, which is what the
    ///     blocked event's own revision is being compared against.
    /// - Returns: The message and ``ArgumentParser/ExitCode/conflict``, or `nil` when
    ///   the step is not a refusal at all.
    static func blocked(
        _ step: UndoStep, editing url: URL, currentRevision: String
    ) -> CommandFailure? {
        switch step {
        case let .blockedByOther(event):
            CommandFailure(
                message: """
                Cannot undo \(url.path): \(event.identity) made a later \(event.op.rawValue) to \
                \(target(of: event)) at \(ActivityEvent.wireTime(event.time)), leaving it at \
                revision \(event.revision). Undo never guesses. See it with \
                `woodcase activity --file \(url.path)`, or pass --all to undo across identities.
                """,
                exitCode: .conflict
            )
        case let .blockedByStale(event):
            CommandFailure(
                message: """
                Cannot undo \(url.path): it is at revision \(currentRevision), but \
                \(event.identity)'s \(event.op.rawValue) to \(target(of: event)) at \
                \(ActivityEvent.wireTime(event.time)) left it at revision \(event.revision) — \
                something changed the file outside the log. Undo never guesses. See the history \
                with `woodcase activity --file \(url.path)`.
                """,
                exitCode: .conflict
            )
        case let .blockedByExternal(event):
            CommandFailure(
                message: """
                Cannot undo \(url.path): cannot undo past an edit made outside woodcase at \
                \(ActivityEvent.clockTime(event.time)), which left it at revision \
                \(event.revision). Nothing woodcase did produced that change, so there is no \
                inverse to replay. See the history with `woodcase activity --file \(url.path)`.
                """,
                exitCode: .conflict
            )
        case .undo, .stepOverUndo, .stepOverUndone, .stepOverRewrite, .reachedCreation:
            nil
        }
    }

    /// The clean negative: the scan ran and found nothing it could reverse.
    ///
    /// - Parameters:
    ///   - url: The .pen file being undone.
    ///   - recorded: How many events the log holds for that file. Zero means nothing
    ///     was ever logged; more than zero means everything logged has been undone
    ///     already — or the file has moved outside the log, which the message says,
    ///     because the two are not distinguishable from the log alone.
    ///   - revision: The document's revision, so a reader can compare it against the
    ///     log's own rows.
    /// - Returns: The message and ``ArgumentParser/ExitCode/cleanNegative``.
    static func nothingToUndo(
        editing url: URL, recorded: Int, revision: String
    ) -> CommandFailure {
        let cause = recorded == 0
            ? "no edits to it are recorded"
            : """
            every recorded edit has already been undone, or the file changed outside the log — \
            it is at revision \(revision)
            """
        return CommandFailure(
            message: """
            Nothing to undo in \(url.path): \(cause). \
            `woodcase activity --file \(url.path)` shows the history.
            """,
            exitCode: .cleanNegative
        )
    }

    /// The refusal to undo anonymously.
    ///
    /// `undo` is the one verb whose *whole* subject is the log, and an undo that names
    /// nobody makes the history unreadable to the people sharing it: the tail would say
    /// an edit was reversed without saying by whom, which is exactly the question the
    /// next reader has. Every other verb is free to write unattributed — the edit is
    /// still recorded, under ``ActivityEvent/unattributed`` — because for those the
    /// name is a courtesy and the record is the point.
    ///
    /// - Returns: The message and ``ArgumentParser/ExitCode/usage``.
    static func missingIdentity() -> CommandFailure {
        CommandFailure(
            message: """
            undo needs an identity: pass `--as <name>`, or set \
            $\(Identity.environmentVariable). An undo is itself a recorded edit, and the \
            history has to say who reversed what.
            """,
            exitCode: .usage
        )
    }

    /// The refusal for `-n 0` and below.
    ///
    /// - Parameter count: The number that was asked for.
    /// - Returns: The message and ``ArgumentParser/ExitCode/usage``.
    static func badCount(_ count: Int) -> CommandFailure {
        CommandFailure(
            message: "-n must be 1 or more; \(count) is not a number of edits to reverse. "
                + "Pass `-n 1` to undo the last one.",
            exitCode: .usage
        )
    }

    /// What an event touched, as a name path, or the document itself for an event that
    /// changed a variable, an import or a theme axis and so names no node.
    private static func target(of event: ActivityEvent) -> String {
        event.paths.first ?? "the document"
    }
}
