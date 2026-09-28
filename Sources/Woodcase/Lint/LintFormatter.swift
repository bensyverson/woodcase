//
//  LintFormatter.swift
//  Woodcase
//

import Foundation

/// Renders ``LintFinding`` values: one grep-able line each for reading, and the JSON
/// array for parsing.
///
/// ## The text form
///
/// ```text
/// warning pipeline  document  [migration] Format version 2.13 has never been observed
/// error broken-ref  Board/Chip (Chi01)  is an instance of `Cmp09`, which this document …
/// warning clipped  Card/Title (x9Kqp)  20,80 160×24 sits partly outside Card (200×100).
/// ```
///
/// Severity and check id first, so `lint … | grep '^error'` and `grep ' clipped '` both
/// work; then the node by name path and by id; then the sentence. The groups are
/// separated by two spaces and the columns are deliberately *not* padded — a finding's
/// line is the same bytes whatever else the run found.
///
/// A finding about the document rather than a node says `document` where the node
/// would be.
public enum LintFormatter {
    /// Renders findings as one line each.
    ///
    /// - Parameter findings: The findings, in the order they should appear.
    /// - Returns: The lines, with no trailing newline. Empty for no findings — a clean
    ///   file says nothing at all.
    public static func text(_ findings: [LintFinding]) -> String {
        findings.map(line).joined(separator: "\n")
    }

    /// Renders findings as the `--json` array: pretty-printed, keys sorted.
    ///
    /// The elements are ``LintFinding`` itself, so the producer and any consumer share
    /// one struct and the wire shape cannot drift.
    ///
    /// - Parameter findings: The findings, in the order they should appear.
    /// - Returns: The JSON text of the array; `"[]"` for no findings.
    /// - Throws: Whatever `JSONEncoder` throws for a value it cannot encode.
    public static func json(_ findings: [LintFinding]) throws -> String {
        guard !findings.isEmpty else { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(findings), as: UTF8.self)
    }

    /// One finding's line.
    private static func line(_ finding: LintFinding) -> String {
        "\(finding.severity.rawValue) \(finding.check.rawValue)  \(target(of: finding))  \(finding.message)"
    }

    /// The node a finding is about: its path and id, or `document` when it is about
    /// the file as a whole.
    private static func target(of finding: LintFinding) -> String {
        switch (finding.path, finding.nodeID) {
        case let (path?, id?): "\(path) (\(id))"
        case let (path?, nil): path
        case let (nil, id?): NodeAddress.marker(forID: id)
        case (nil, nil): "document"
        }
    }
}
