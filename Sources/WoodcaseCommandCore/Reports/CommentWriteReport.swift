//
//  CommentWriteReport.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// What `comment`, `reply` and `resolve` answer with: what was written, the revision to
/// guard the next edit of it with, and the document's.
///
/// ```text
/// reply  Rp7Qx  thread Cm01
/// rev  4f2a1b0c9d8e7f60
/// document  a1b2c3d4e5f60718
/// ```
///
/// The first line leads with what happened — `thread`, `reply`, `resolved` or `open` —
/// then the id to quote next: the new message's, or the thread's for a state change. A
/// state the thread already had writes nothing, and says so instead of the revisions. A
/// dry run prints ``DryRunOption/marker`` first and no revisions, as every write does.
struct CommentWriteReport: Friendly {
    /// What a comment verb did.
    enum Action: String, Friendly {
        /// Started a thread.
        case thread
        /// Added a reply.
        case reply
        /// Set the thread's state to resolved.
        case resolved
        /// Set the thread's state to open.
        case open
    }

    /// What was done.
    var action: Action
    /// The thread's id: its first message's.
    var thread: String
    /// The message written; for a state change, the first message.
    var message: String
    /// When a new message was written, in UTC; `nil` for a state change.
    var createdAt: String?
    /// Whether the thread already had the state asked for, so nothing was written.
    var unchanged: Bool
    /// Whether this was a rehearsal.
    var dryRun: Bool
    /// The written message's revision after the edit; `nil` on a dry run or no change.
    var rev: String?
    /// The document's revision after the edit; `nil` on a dry run or no change.
    var documentRevision: String?

    /// The outline form.
    var text: String {
        var lines: [String] = []
        if dryRun { lines.append(DryRunOption.marker) }
        switch action {
        case _ where unchanged:
            lines.append("\(thread) is already \(action.rawValue); nothing written")
        case .thread:
            lines.append("thread  \(message)")
        case .reply:
            lines.append("reply  \(message)  thread \(thread)")
        case .resolved, .open:
            lines.append("\(action.rawValue)  \(thread)")
        }
        if let rev { lines.append("rev  \(rev)") }
        if let documentRevision { lines.append("document  \(documentRevision)") }
        return lines.joined(separator: "\n")
    }

    /// The report in whichever form was asked for.
    ///
    /// - Parameter json: Whether `--json` was passed.
    /// - Returns: The text to print on standard output.
    /// - Throws: Whatever `JSONEncoder` throws.
    func rendered(json: Bool) throws -> String {
        guard json else { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }
}
