//
//  ViewLogging.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// How a read verb records what it read: one ``Woodcase/ViewEvent`` in the
/// ``Woodcase/ViewLog`` beside the file's activity log, when it has a reader.
///
/// Every read verb calls this once, after its read has finished and outside the file's
/// lock, so a slow or contended views file never holds a writer up. It is best effort by
/// design: the read is the verb's work, and a views file that cannot be written — a
/// read-only directory, a lock held past ``timeout`` — costs the editor a cursor, not
/// the agent its answer. So nothing is printed and the exit status is untouched.
enum ViewLogging {
    /// How long a read waits for another process's lock on the views file before
    /// giving up on recording.
    static let timeout: Duration = .seconds(1)

    /// Records one read, if there is a reader.
    ///
    /// - Parameters:
    ///   - verb: The verb that read.
    ///   - url: The document as named on the command line: a `.pen` or a bundle.
    ///   - identity: The reader, from ``IdentityOptions`` in the
    ///     ``Identity/Reader`` role; `nil` records nothing.
    ///   - revision: The document's revision as read.
    ///   - nodes: The node ids read, in the order printed.
    ///   - scope: Whether the read covered the nodes alone or their subtrees.
    ///   - covered: How many nodes the read covered, when more than `nodes` names.
    static func record(
        _ verb: ViewEvent.Verb,
        of url: URL,
        by identity: String?,
        revision: String,
        nodes: [String],
        scope: ViewEvent.Scope = .nodes,
        covered: Int? = nil
    ) async {
        guard let identity else { return }
        let event = ViewEvent(
            identity: identity, file: url, verb: verb, revision: revision,
            nodes: nodes, scope: scope, covered: covered
        )
        let log = ViewLog(beside: ActivityLogLocation.log(for: url))
        _ = try? await log.record(event, timeout: timeout)
    }
}
