//
//  LintFormatter+Catalogue.swift
//  Woodcase
//

import Foundation

/// The two reads that are about the *checks* rather than about one file's findings:
/// the catalogue `lint --list` prints, and the per-check counts `lint --summary` prints.
///
/// Both keep ``LintFormatter``'s house shape — severity, then check id, then two spaces,
/// then the payload — so a reader who has seen one finding line can read either without
/// learning a second layout, and `grep '^error'` selects the same things in all three.
///
/// ```text
/// $ woodcase lint --list
/// warning pipeline  A diagnostic from the parse, migration, font or render pipeline.
/// error broken-ref  A component instance whose component this document does not define.
///
/// $ woodcase lint design.pen --summary
/// warning clipped  57
/// error unknown-icon  2
/// ```
public extension LintFormatter {
    /// Renders the check catalogue as one line each.
    ///
    /// - Parameter checks: The checks to list, in the order they should appear.
    /// - Returns: The lines, with no trailing newline. Empty when every check was
    ///   filtered out.
    static func list(_ checks: [LintCheck]) -> String {
        checks
            .map { "\($0.severity.rawValue) \($0.rawValue)  \($0.summary)" }
            .joined(separator: "\n")
    }

    /// Renders the check catalogue as the `--json` array: pretty-printed, keys sorted.
    ///
    /// The elements are ``LintCheckDescription``, so the catalogue's wire shape is a
    /// struct rather than a hand-written object literal.
    ///
    /// - Parameter checks: The checks to list, in the order they should appear.
    /// - Returns: The JSON text of the array; `"[]"` for no checks.
    /// - Throws: Whatever `JSONEncoder` throws for a value it cannot encode.
    static func listJSON(_ checks: [LintCheck]) throws -> String {
        let rows = checks.map(LintCheckDescription.init)
        guard !rows.isEmpty else { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(rows), as: UTF8.self)
    }

    /// Renders findings as one row per check that fired, with how many it found.
    ///
    /// A check that found nothing has no row: the report is what the run *has to say*,
    /// and fourteen zeroes around one number is the number harder to see. Rows are in
    /// ``LintCheck``'s own declaration order, so two runs of the same file print the
    /// same bytes and two different files line up when they are read side by side.
    ///
    /// - Parameter findings: The findings to count, already filtered by whatever the
    ///   caller excluded.
    /// - Returns: The rows, with no trailing newline. Empty for no findings — a clean
    ///   file says nothing at all, exactly as ``text(_:)`` does.
    static func summary(_ findings: [LintFinding]) -> String {
        let counts = counts(of: findings)
        return LintCheck.allCases
            .compactMap { check in
                counts[check].map { "\(check.severity.rawValue) \(check.rawValue)  \($0)" }
            }
            .joined(separator: "\n")
    }

    /// Renders the per-check counts as the `--json` object: pretty-printed, keys sorted.
    ///
    /// An object keyed by check id rather than an array of rows, because that is the
    /// shape a caller reads a single count out of — `.["clipped"] // 57` — and a check
    /// that found nothing is absent rather than zero, matching the text form.
    ///
    /// - Parameter findings: The findings to count.
    /// - Returns: The JSON text of the object; `"{}"` for no findings.
    /// - Throws: Whatever `JSONEncoder` throws for a value it cannot encode.
    static func summaryJSON(_ findings: [LintFinding]) throws -> String {
        let counts = counts(of: findings)
        guard !counts.isEmpty else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let byID = Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
        return try String(decoding: encoder.encode(byID), as: UTF8.self)
    }

    /// How many findings each check that fired produced.
    ///
    /// The one place the counting happens, so the text and the JSON forms can never
    /// disagree about a number or about which checks are present at all.
    private static func counts(of findings: [LintFinding]) -> [LintCheck: Int] {
        findings.reduce(into: [:]) { counts, finding in
            counts[finding.check, default: 0] += 1
        }
    }
}
