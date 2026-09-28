//
//  OutsideWriteNote.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The note a write prints when it finds the file was rewritten outside woodcase.
///
/// ```text
/// note  /Users/ana/Designs/banking.pen was rewritten outside woodcase since rev
/// 9c1b04e6 (ana, 10:32); the log has no record of that change
/// ```
///
/// The sentence is ``Woodcase/LogLineage/note(naming:)``'s — the library detects it, the
/// verb says it — and the `note  ` marker is the one ``Woodcase/WriteDivergence`` uses,
/// so a reader scanning the left margin sees one vocabulary. It is a note and not a
/// warning because nothing is wrong: the edit landed, and the file may have been changed
/// for perfectly good reasons. What it says is that the history has a hole in it, and
/// where the hole starts.
///
/// It prints once per hole: the transaction that finds one records an
/// ``Woodcase/ActivityEvent/Kind/external`` row for it, so the writes after that are
/// quiet again.
///
/// ## Where it goes
///
/// Standard output, with the answer, in the ordinary text form. Under `--json` it goes
/// to standard error instead: the answer there is one JSON document and a line of prose
/// in front of it would break the pipe that reads it. That is the same reason
/// ``RootOverlapWarnings`` writes where it does.
enum OutsideWriteNote {
    /// Prints the note a transaction's outcome carries, if it carries one.
    ///
    /// - Parameters:
    ///   - outcome: The finished transaction.
    ///   - json: Whether the verb is answering in JSON, which decides which stream the
    ///     note goes to.
    static func report(_ outcome: PenFileTransaction.Outcome<some Sendable>, json: Bool) {
        guard let note = outcome.lineage.note(naming: outcome.url) else { return }
        let line = "note  \(note)"
        if json {
            StandardError.write(line)
        } else {
            print(line)
        }
    }
}
