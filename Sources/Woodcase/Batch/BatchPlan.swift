//
//  BatchPlan.swift
//  Woodcase
//

import Foundation

/// One batch line, resolved against the document and translated into edits.
///
/// The step between the grammar and ``EditOperation``: addresses have become
/// ids, a `rev` has become a revision to check, and an authored subtree has
/// become a subtree with ids the document does not already hold. Planning
/// never mutates, so a line that cannot be planned fails before anything
/// changes.
///
/// Holding the translated edits is also what makes `--atomic` exact: the
/// applier plans and applies against a copy, and replays *these* operations —
/// ids and all — onto the real document, so the ids a report promises are the
/// ids the document ends up with.
struct BatchPlan {
    /// The edits to apply, in order.
    var operations: [EditOperation]

    /// Revisions to check before the first edit, keyed by node id.
    var expecting: [String: String] = [:]

    /// The whole document's expected revision, for a line that guards no single node.
    var expectedDocumentRevision: String?

    /// The root id of the subtree this line creates, if it creates one.
    var createdRootID: String?

    /// The id of the node this line acts on, for the report's name path.
    var actedOnID: String?

    /// The ways this line's result will differ from the line as it was written.
    ///
    /// Decided here because planning is the one place both halves exist at once: the
    /// operation as the caller wrote it, and the document it is about to change. Empty
    /// for the ordinary write, which is what keeps the report quiet.
    var divergences: [WriteDivergence] = []
}
