//
//  WriteEffect.swift
//  Woodcase
//

import Foundation

/// What a ``PenFileTransaction`` does with the document its body leaves behind.
///
/// A dry run is not a different transaction: it takes the same exclusive lock, parses
/// the same bytes, runs the same body, checks the same guards and settles the same
/// layout. It differs at the last step only — the rename over the file and the append to
/// the activity log are skipped, so the file's bytes, its revisions, the log and any
/// `.gitignore` the log would have edited are exactly what they were.
///
/// ```swift
/// let outcome = try await PenFileTransaction.run(
///     at: url, identity: "ana", effect: .dryRun
/// ) { document, recorder in
///     let preview = try LintPreview(of: document)
///     try recorder.apply(edit)
///     return try preview.introduced(in: document)
/// }
/// outcome.commit    // .previewed — it would have written
/// ```
///
/// The point of running the whole transaction rather than simulating it is that the
/// premise is the same: a `--guard` that a real write would refuse is refused here too,
/// with the same message and the same exit code, and a caller who rehearses a write and
/// then commits it is not told two different things.
///
/// Pair it with ``LintPreview`` to answer the question a rehearsal exists for — what
/// would this write break? — without writing first.
public enum WriteEffect: String, Friendly, CaseIterable {
    /// Write the result back and log it: the ordinary write.
    case commit

    /// Roll the result back and log nothing, having done everything else.
    case dryRun
}
