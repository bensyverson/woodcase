//
//  LintCheckDescription.swift
//  Woodcase
//

import Foundation

/// One row of the check catalog: what `lint --list` prints and what its `--json`
/// carries.
///
/// Everything here is derived from ``LintCheck`` — the id, the severity its findings
/// carry, the one line saying what it looks for — and none of it is stored anywhere
/// else. It exists as a struct rather than a dictionary so the catalog's wire shape
/// is a type both the producer and any consumer can hold, the same way ``LintFinding``
/// is the wire shape of a finding.
///
/// ```swift
/// print(LintFormatter.list(LintCheck.allCases))
/// // error broken-ref  A component instance whose component this document does not define.
/// ```
public struct LintCheckDescription: Friendly {
    /// Describes one check.
    ///
    /// - Parameter check: The check to describe. Everything else follows from it.
    public init(_ check: LintCheck) {
        self.check = check
        severity = check.severity
        summary = check.summary
    }

    /// The check's stable id — what `--exclude` takes and what a finding prints.
    public let check: LintCheck

    /// The severity this check's findings normally carry.
    public let severity: PenDiagnostic.Severity

    /// One line saying what the check looks for.
    public let summary: String
}
