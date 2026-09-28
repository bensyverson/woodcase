//
//  NewFileReport.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// What `woodcase new` answers with: the file it wrote, and the revision the first
/// edit of it can be guarded with.
///
/// `new` creates no node, so it has nothing in common with ``Woodcase/WriteReport`` beyond
/// the shape of the two answers a write gives: what happened, and the revision to
/// carry forward. Every file `new` writes is identical — the current format version
/// and empty children — so ``documentRevision`` is always the same hash.
///
/// ```text
/// design.pen
/// document  a1b2c3d4e5f60718
/// ```
///
/// A `--dry-run` prints the path between ``DryRunOption/marker`` and the findings the
/// file would carry, and no revision — nothing was created, so the revision names
/// nothing on disk.
struct NewFileReport: Friendly {
    /// Creates a report.
    ///
    /// - Parameters:
    ///   - path: The path of the file that was created, as typed on the command line.
    ///   - documentRevision: The fresh document's revision.
    ///   - dryRun: Whether this was a rehearsal. A rehearsal drops the revision and
    ///     gains the marker and the findings. See ``DryRunOption``.
    ///   - lint: The findings the file would carry. Every one of them is introduced,
    ///     because before this command there is no file — so unlike the other verbs
    ///     there is nothing to difference against. The document `new` writes is fixed
    ///     and empty, so in practice this is empty too.
    init(path: String, documentRevision: String, dryRun: Bool = false, lint: [LintFinding] = []) {
        self.path = path
        self.documentRevision = dryRun ? nil : documentRevision
        self.dryRun = dryRun ? true : nil
        self.lint = dryRun ? lint : nil
    }

    /// The path of the file that was created, as typed on the command line.
    let path: String

    /// The fresh document's revision, or `nil` for a dry run — which created no file
    /// for it to name.
    let documentRevision: String?

    /// `true` when nothing was written, `nil` when something was.
    let dryRun: Bool?

    /// The lint findings the created file would carry, or `nil` for a real write.
    let lint: [LintFinding]?

    /// The outline form: the path, then the revision.
    var text: String {
        var lines: [String] = dryRun == true ? [DryRunOption.marker] : []
        lines.append(path)
        if let documentRevision {
            lines.append("document  \(documentRevision)")
        }
        if let lint, !lint.isEmpty {
            lines.append(LintFormatter.text(lint))
        }
        return lines.joined(separator: "\n")
    }

    /// The `--json` form.
    ///
    /// - Returns: The JSON text of this report.
    /// - Throws: Whatever `JSONEncoder` throws.
    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }

    /// The report in whichever form was asked for.
    ///
    /// - Parameter json: Whether `--json` was passed.
    /// - Returns: The text to print on standard output.
    /// - Throws: Whatever `JSONEncoder` throws.
    func rendered(json wantsJSON: Bool) throws -> String {
        wantsJSON ? try json() : text
    }
}
