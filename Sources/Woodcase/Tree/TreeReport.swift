//
//  TreeReport.swift
//  Woodcase
//

import Foundation

/// The `--json` shape of a settled tree read: the rows, and the document revision
/// they were read at.
///
/// The report's own revision is ``EditableDocument/documentRevision`` — the whole
/// file, which churns under any writer. The pin a caller usually wants is narrower and
/// rides on the rows: every ``TreeRow/rev`` is that node's
/// ``EditableDocument/revision(of:)``, covering its whole subtree. A caller that
/// reasons about one frame and then writes passes that frame's `rev` back — see
/// ``EditableDocument/apply(_:expecting:)`` — so a subtree that changed underneath
/// fails loudly instead of silently applying to a different tree, while an edit
/// somewhere else in the file does not get in the way.
///
/// This is the one struct both the producer (``TreeFormatter/json(_:revision:)``) and
/// any consumer decode, so the wire shape cannot drift.
public struct TreeReport: Friendly {
    /// The document revision the rows were read at.
    public let revision: String

    /// The rows, in pre-order.
    public let rows: [TreeRow]

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - revision: The document revision the rows were read at.
    ///   - rows: The rows, in pre-order.
    public init(revision: String, rows: [TreeRow]) {
        self.revision = revision
        self.rows = rows
    }
}
