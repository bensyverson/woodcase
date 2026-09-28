//
//  DryRunOption.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// The `--dry-run` flag every mutating verb includes.
///
/// A rehearsal, not a simulation: the verb takes the file's exclusive lock, checks its
/// guards, applies the edit, settles the layout and builds exactly the answer it would
/// have printed — and then the transaction rolls the whole thing back. The file's bytes,
/// its revisions and the activity log are what they were, and no `.gitignore` line is
/// added. See ``Woodcase/WriteEffect``.
///
/// `new` is the one verb that cannot work that way, because there is no file yet to
/// lock: its rehearsal runs both refusals and then answers without creating anything,
/// which is the whole of what it would have done.
///
/// ```bash
/// woodcase add design.pen Board -F card.json --dry-run
/// woodcase apply design.pen -F ops.jsonl --dry-run --json
/// ```
///
/// What comes back is the write's own report — ``WriteReport`` for the eight verbs that
/// go through ``Woodcase/BatchApplier``, and each of `vars set`, `vars rm`,
/// `vars axis add`, `undo` and `new`'s own shape for the rest — with two differences.
///
/// - A marker leads standard output — ``marker`` — so a caller reading a log cannot
///   mistake a rehearsal for a write. `--json` carries `"dryRun": true` instead; a
///   marker line would not parse.
/// - **No revision.** A dry run leaves the file at the revision it already had, so the
///   revision the write *would* have produced names nothing on disk. `rm` already
///   refuses to print a node revision for a node it deleted, for the same reason: a
///   plausible wrong answer is worse than a missing one. Rehearse, then run the verb
///   for real, and read the revision from that.
///
/// Then the findings the result would introduce, from ``Woodcase/LintPreview`` — the
/// *new* ones only, so a file that already lints dirty does not bury the answer. Their
/// lines are `lint`'s own bytes, so `--dry-run | grep '^error'` reads the same as
/// `lint | grep '^error'`. Findings do not change the exit code: the exit code is the
/// write's, so a rehearsed guard conflict is still 3 and a rehearsed clean write is
/// still 0.
struct DryRunOption: ParsableArguments {
    @Flag(
        name: .long,
        help: """
        Rehearse: run the whole write — its refusals, its guards and its settling \
        included — print the answer it would give plus the lint findings it would \
        introduce, and keep none of it. The file, its revisions and the activity log \
        are untouched, and no revision is printed because none was made.
        """
    )
    var dryRun: Bool = false

    /// What the transaction should do with the document the verb leaves behind.
    var effect: WriteEffect {
        dryRun ? .dryRun : .commit
    }

    /// The line a rehearsal leads its standard output with.
    ///
    /// Two spaces between the label and the sentence, the same column separator every
    /// other row of a write's answer uses. It is a fixed string on purpose: a caller
    /// grepping for it, or a human scrolling a log, gets the same bytes every time.
    static let marker = "dry run  nothing written"
}
