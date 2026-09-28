//
//  BatchLineStatus.swift
//  Woodcase
//

import Foundation

/// What became of one line of a batch.
///
/// The three statuses are the whole contract of ``BatchApplier``: a batch
/// applies what it can, so a failure is local to its line, and a line that
/// could only have depended on a failure is distinguished from one that was
/// tried and rejected. Only ``failed`` means "this line is wrong".
public enum BatchLineStatus: String, Friendly {
    /// The operation ran and the document changed.
    case applied

    /// The operation was attempted and rejected. ``BatchLineResult/error`` says why.
    ///
    /// The line changed nothing: an operation that expands to several edits is
    /// rolled back if a later edit in the same line fails.
    case failed

    /// The operation was never attempted, because a line it depends on failed.
    ///
    /// A line cascades when it names a tag a failed line declared, or addresses
    /// a node a failed line would have created or was the target of. In
    /// ``BatchApplier/apply(_:to:atomic:identity:recorder:)``'s atomic mode every line
    /// other than the culprit cascades, because the whole batch was discarded.
    case cascaded
}
