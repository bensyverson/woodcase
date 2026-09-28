//
//  WriteReport+Formatting.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders ``Woodcase/WriteReport`` — the answer every mutating verb gives — as the
/// CLI's two output shapes.
///
/// The report itself is a plain data value in the library; everything about *how* it
/// prints lives here, as functions of that value, so a library caller (the report
/// itself) never carries formatting it does not need.
extension WriteReport {
    /// The outline form: the tree or the acted-on node, what diverged, then the
    /// revisions.
    ///
    /// Two spaces between a name and its id, one row per fact, no trailing newline —
    /// the same bytes every time, so a golden test can pin them. A write whose result
    /// is what was asked for prints no divergence line at all, so the common case is
    /// byte-for-byte what it was before the echo existed.
    ///
    /// Each divergence prints its ``Woodcase/WriteDivergence/reportLine``, so a
    /// ``Woodcase/WriteDivergence/Severity/note`` — a sentence about what the write
    /// *did*, rather than about what it means — carries its marker and cannot be read
    /// as a warning.
    var text: String {
        var lines: [String] = []
        if dryRun == true {
            lines.append(DryRunOption.marker)
        }
        if let created {
            lines.append(CreatedTreeFormatter.text(created))
        } else if let path, let id {
            lines.append("\(path)  \(id)")
        }
        lines.append(contentsOf: divergences?.map(\.reportLine) ?? [])
        if let nodeRevision {
            lines.append("rev  \(nodeRevision)")
        }
        if let documentRevision {
            lines.append("document  \(documentRevision)")
        }
        if let lint, !lint.isEmpty {
            lines.append(LintFormatter.text(lint))
        }
        return lines.joined(separator: "\n")
    }

    /// The `--json` form: the same facts under stable keys.
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
