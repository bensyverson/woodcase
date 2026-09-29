//
//  LintFinding.swift
//  Woodcase
//

import Foundation

/// One thing ``DocumentLinter`` found: which check fired, how bad it is, which node it
/// is about, and what to do.
///
/// A finding names its node twice — by ``path``, which is what a later command should
/// pass, and by ``nodeID``, which is what the file stores — because the path is what a
/// reader recognizes and the id is what survives a rename. A finding about the document
/// as a whole (a version-gate warning, say) carries neither.
///
/// ``LintFormatter`` renders findings; the `lint` verb prints them and exits 1 when
/// there are any.
public struct LintFinding: Friendly {
    /// The check that produced this finding.
    public let check: LintCheck

    /// How bad it is. Normally ``LintCheck/severity``; a ``LintCheck/pipeline``
    /// finding carries the diagnostic's own severity instead.
    public let severity: PenDiagnostic.Severity

    /// The id of the node the finding is about, or `nil` for a document-level finding.
    public let nodeID: String?

    /// The node's name path (`"Dashboard/Header/Title"`), or `nil` for a
    /// document-level finding.
    public let path: String?

    /// What is wrong, and — where there is one — what to do about it.
    public let message: String

    /// Creates a finding.
    ///
    /// - Parameters:
    ///   - check: The check that fired.
    ///   - severity: How bad it is. Defaults to the check's own severity.
    ///   - nodeID: The node's id, or `nil` for a document-level finding.
    ///   - path: The node's name path, or `nil` for a document-level finding.
    ///   - message: What is wrong, and what to do about it.
    public init(
        check: LintCheck,
        severity: PenDiagnostic.Severity? = nil,
        nodeID: String?,
        path: String?,
        message: String
    ) {
        self.check = check
        self.severity = severity ?? check.severity
        self.nodeID = nodeID
        self.path = path
        self.message = message
    }
}
