//
//  ScriptRunReport.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase
import WoodcaseScripting

/// What one `woodcase js` run says back: the host's ``WoodcaseScripting/ScriptRun``,
/// plus the three things only the verb's transaction knows.
///
/// The transcript and `--json` are two pure functions of *this* value — see
/// ``ScriptRunFormatter`` — so the two forms cannot disagree about what happened. The
/// verb builds one of these once, after the transaction has ended, and prints it in
/// whichever form was asked for.
///
/// Three fields the host cannot supply, because it holds a document and never a file:
///
/// - ``commit`` is the transaction's answer mapped over the host's — ``ScriptRun/Commit/previewed``
///   for a `--dry-run`, and ``ScriptRun/Commit/unchanged`` for a script that wrote and
///   then wrote back, which the host reports as `wrote` because the script did write.
/// - ``warnings`` are the root overlaps the run created, rendered from the run's own
///   ``WoodcaseScripting/ScriptRun/Event/overlap(_:)`` events — the host takes the
///   before-and-after `apply` takes, so the verb reads the timeline rather than diffing
///   the document a second time.
/// - ``lint`` and ``dryRun`` are the rehearsal's findings and its marker.
///
/// ``documentRevision`` is `nil` for a rehearsal and for a run that rolled back, for
/// ``Woodcase/WriteReport``'s reason: neither made a revision, and printing the one the
/// document would have reached names nothing on disk.
struct ScriptRunReport: Friendly {
    /// Builds the report for a finished run.
    ///
    /// - Parameters:
    ///   - run: What the host answered with.
    ///   - commit: How the transaction ended, mapped over the host's own answer.
    ///   - lint: The findings a rehearsal would introduce, or empty.
    ///   - dryRun: Whether this was a rehearsal.
    init(
        run: ScriptRun,
        commit: ScriptRun.Commit,
        lint: [LintFinding] = [],
        dryRun: Bool = false
    ) {
        events = run.events.map(Event.init)
        let warnings = run.events.compactMap { event in
            if case let .overlap(finding) = event { RootOverlapWarnings.line(of: finding) } else { nil }
        }
        result = run.result
        documentRevision = if dryRun {
            nil
        } else {
            switch commit {
            case .wrote, .unchanged: run.documentRevision
            case .previewed, .rolledBack: nil
            }
        }
        self.commit = commit
        error = run.error
        self.warnings = warnings.isEmpty ? nil : warnings
        self.dryRun = dryRun ? true : nil
        self.lint = dryRun && !lint.isEmpty ? lint : nil
    }

    /// What happened, in the order it happened.
    let events: [Event]

    /// The completion value of the last source, or `nil` when there was none.
    let result: AnyCodable?

    /// The revision the file was left at, or `nil` when this run made none.
    let documentRevision: String?

    /// How the run ended for the file on disk.
    let commit: ScriptRun.Commit

    /// Why the run ended early, or `nil` when it reached the end of the last source.
    let error: ScriptError?

    /// The artboards this run left overlapping, or `nil` when it left none.
    let warnings: [String]?

    /// `true` for a rehearsal, `nil` for a real run — so a real run's JSON is exactly
    /// the bytes it was before `--dry-run` existed, as ``Woodcase/WriteReport``'s is.
    let dryRun: Bool?

    /// The findings the rehearsed run would introduce, or `nil`.
    let lint: [LintFinding]?

    // MARK: - Event

    /// One event of the timeline, in the shape `--json` prints it.
    ///
    /// A rendering of ``WoodcaseScripting/ScriptRun/Event`` rather than the enum
    /// itself: Swift's synthesized `Codable` for an enum with an unlabelled payload
    /// writes `{"write":{"_0":…}}`, and `_0` is not a key a caller should have to know.
    /// This is the CLI's wire shape, the way ``Woodcase/BatchReport``'s rows are — one
    /// discriminator and the fields that kind carries.
    struct Event: Friendly {
        /// Renders one of the host's events.
        ///
        /// - Parameter recorded: The event to render.
        init(_ recorded: ScriptRun.Event) {
            switch recorded {
            case let .write(member, report):
                event = .write
                self.member = member
                write = report
                level = nil
                text = nil
            case let .log(level, text):
                event = .log
                member = nil
                write = nil
                self.level = level
                self.text = text
            case let .warning(text):
                event = .warning
                member = nil
                write = nil
                level = nil
                self.text = text
            case let .overlap(finding):
                event = .overlap
                member = nil
                write = nil
                level = nil
                text = RootOverlapWarnings.line(of: finding)
            }
        }

        /// Which kind of event this is.
        let event: Kind

        /// Which member of `doc` made the write, for a ``Kind/write``.
        ///
        /// The transcript's first column, and the one thing a
        /// ``Woodcase/WriteReport`` cannot say: it names what was touched, never what
        /// touched it.
        let member: ScriptWriteMember?

        /// The write's own echo, for a ``Kind/write``.
        let write: WriteReport?

        /// Which `console` member printed the line, for a ``Kind/log``.
        let level: ScriptLogLevel?

        /// The line, for a ``Kind/log``, a ``Kind/warning`` or a ``Kind/overlap``.
        ///
        /// An overlap arrives as a ``Woodcase/LintFinding`` and is rendered here with
        /// ``Woodcase/LintFormatter``, so the line is the one `apply` and `lint` print
        /// for the same pair, prefix and all.
        let text: String?

        /// The four things that can happen during a run.
        enum Kind: String, Friendly, CaseIterable {
            /// A write, carrying the report the matching verb prints.
            case write

            /// A `console` line, with the level that decides its stream.
            case log

            /// Something the run wants said that is not a refusal.
            case warning

            /// A root overlap the run created, already rendered as `lint` prints it.
            case overlap
        }
    }
}
