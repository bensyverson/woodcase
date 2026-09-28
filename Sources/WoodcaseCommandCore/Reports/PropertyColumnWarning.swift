//
//  PropertyColumnWarning.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Says on standard error that a `--props` column came back empty on every row.
///
/// A column of dashes is what an unprefixed path (`content` rather than `kind.content`)
/// produces, and a typo that reads as an answer is worse than one that reads as an
/// error. The rows themselves are unaffected — stdout stays parseable and the exit code
/// is whatever the verb decided — because an empty column is a legitimate result when
/// no node in the subtree happens to carry that property.
///
/// `find` needs the warning more than `tree` does: a predicate reading a mistyped path
/// answers `undefined` for every row, so the run prints nothing and exits 1, and this
/// sentence is the only thing that says why.
enum PropertyColumnWarning {
    /// Writes one line per requested path that no row carries.
    ///
    /// The default columns say nothing: a caller who wrote a bare `--props` named no path,
    /// so an empty one among them is the verb's choice rather than their typo.
    ///
    /// When every row in the listing is a component instance and the walk did not expand
    /// them, an empty column is not a typo either — it is the property grammar working as
    /// designed against rows whose children, where the property most likely lives, were
    /// never read. `tree <ref> --props kind.content` on a bare instance reads exactly this
    /// way, so the sentence adds `--expand` rather than leaving the reader to restate the
    /// same guess a second time.
    ///
    /// - Parameters:
    ///   - properties: The property paths that were asked for.
    ///   - rows: The rows the columns were read onto — every row the walk produced, not
    ///     only the ones a verb went on to print.
    ///   - expand: Whether the walk expanded component instances. `false` is what lets an
    ///     unexpanded ref's empty column earn the `--expand` remedy.
    static func warnAboutEmptyColumns(_ properties: [String], in rows: [TreeRow], expand: Bool) {
        guard properties != Tree.defaultPropertyPaths else { return }
        let onlyUnexpandedInstances = !expand && !rows.isEmpty && rows.allSatisfy(\.isInstance)
        for path in properties where !rows.contains(where: { $0.properties?[path] != nil }) {
            var message = "--props: no node in this listing has \"\(path)\". Property paths are prefixed — "
                + "\"common.name\", \"kind.content\", \"kind.fill\"."
            if onlyUnexpandedInstances {
                message += " Every row here is a component instance with its children left out of the "
                    + "listing — pass --expand to walk into them and read their properties."
            }
            StandardError.write(message)
        }
    }
}
