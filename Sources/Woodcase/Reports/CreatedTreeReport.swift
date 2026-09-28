//
//  CreatedTreeReport.swift
//  Woodcase
//

import Foundation

/// The `--json` shape of what a mutating verb made: the subtrees, and the document
/// revision the write left behind.
///
/// Every mutating verb answers with the name → id tree this wraps, because the next
/// command needs the ids and a second lookup to learn them is a round trip an agent
/// should not have to pay for. This is the wire shape; the outline text a terminal
/// reads is a rendering of the same ``created`` list, not a second source of truth.
public struct CreatedTreeReport: Friendly {
    /// Creates a report.
    ///
    /// - Parameters:
    ///   - created: The subtrees the verb made, in the order it made them.
    ///   - revision: The document revision the write left behind.
    public init(created: [CreatedNode], revision: String) {
        self.created = created
        self.revision = revision
    }

    /// The subtrees the verb made.
    public let created: [CreatedNode]

    /// The document revision the write left behind.
    public let revision: String
}
