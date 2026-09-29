//
//  RootOverlapWarnings.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The warning a write prints when it leaves one artboard sitting on another.
///
/// Artboards do not overlap. A write that creates an overlap is still applied — the
/// caller may be mid-edit, and refusing would cost more than it saved — but it says so:
/// one line on standard error per pair it created, in exactly the form `lint` prints
/// the same finding, so the two are recognizably one fact.
///
/// ```text
/// warning artboard-overlap  Checkout (Chk01)  100,0 200×100 overlaps Home (Home1) …
/// ```
///
/// Only pairs the write **created** are reported. An overlap that was already in the
/// file is `lint`'s business; repeating it on every unrelated edit would train a caller
/// to ignore the line. That is why the check is a before-and-after — and why the diff
/// itself is ``Woodcase/RootOverlap/introduced(since:in:)``, in the library beside the
/// geometry: `woodcase js` is not the only caller that writes, and
/// ``WoodcaseScripting/ScriptRun/Event/overlap(_:)`` carries the same finding to a
/// library caller that never goes through a verb.
enum RootOverlapWarnings {
    /// The overlapping pairs a document has right now, and the text sizes that measured
    /// them.
    ///
    /// - Parameter document: The document, as it stands.
    /// - Returns: The baseline to compare a later state against; its text sizes let the
    ///   measurement after the edit typeset only the texts the edit changed.
    static func baseline(in document: EditableDocument) -> RootOverlap.Baseline {
        RootOverlap.baseline(in: document)
    }

    /// The warning lines for every overlap that was not there before.
    ///
    /// - Parameters:
    ///   - before: What ``baseline(in:)`` measured before the edit.
    ///   - document: The document after the edit.
    ///   - file: The .pen file being edited, named in the suggested remedy.
    /// - Returns: One line per newly overlapping pair, in document order. Empty when
    ///   the edit created none.
    static func lines(since before: RootOverlap.Baseline, in document: EditableDocument, file: String) -> [String] {
        RootOverlap.introduced(since: before, in: document)
            .map { line(of: $0.finding(in: document, file: file)) }
    }

    /// One finding's line, as `lint` prints it.
    ///
    /// - Parameter finding: The finding to render.
    /// - Returns: The line.
    static func line(of finding: LintFinding) -> String {
        LintFormatter.text([finding])
    }

    /// Writes the lines to standard error, where everything a verb says about its work
    /// goes.
    ///
    /// - Parameter lines: The warning lines, or an empty array to say nothing.
    static func report(_ lines: [String]) {
        for line in lines {
            StandardError.write(line)
        }
    }
}

/// What a mutating verb hands back out of its transaction: the answer for standard
/// output, and the warnings for standard error.
///
/// The two are separated here rather than printed inside the transaction because a
/// transaction that fails after the body runs must not have warned about a write that
/// never landed.
struct WrittenOutcome {
    /// Creates an outcome.
    ///
    /// - Parameters:
    ///   - rendered: The verb's answer, in whichever form was asked for.
    ///   - warnings: The warning lines, in the order to print them.
    init(rendered: String, warnings: [String] = []) {
        self.rendered = rendered
        self.warnings = warnings
    }

    /// The verb's answer, for standard output.
    let rendered: String

    /// The warning lines, for standard error.
    let warnings: [String]
}
