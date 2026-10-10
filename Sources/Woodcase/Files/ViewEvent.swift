//
//  ViewEvent.swift
//  Woodcase
//

import Foundation

/// One line of the view log: an identity read some nodes of a document, at a revision.
///
/// A read verb (`tree`, `get`, `find`, `shot`, `render`) run with an identity writes one,
/// so an editor can show what an agent looked at and "did it look before it changed
/// this?" has an answer. It is written to `views.jsonl` (``ViewLog``), never to
/// `activity.jsonl`: a view changes nothing, and every invariant of the write history —
/// ``LogLineage``'s newest revision, the undo walk, change attribution — reads that log
/// alone.
///
/// ```json
/// {"covered":1,"file":"/Users/agent/Designs/demo.pen","identity":"claude",
///  "nodes":["jSUCH"],"revision":"3f2a91c0d4e5b678","scope":"subtrees",
///  "time":"2026-10-04T16:31:04.123Z","verb":"get"}
/// ```
public struct ViewEvent: Friendly {
    /// The most nodes a view keeps: the first ones the verb printed. ``covered`` says
    /// how many the read covered in all.
    public static let nodeLimit = 64

    /// Records one read.
    ///
    /// - Parameters:
    ///   - time: When the read happened. Rounded to the millisecond.
    ///   - identity: The reader's `--as` name.
    ///   - file: The document read; stored canonically, as ``ActivityEvent/file`` is.
    ///   - verb: The verb that read it.
    ///   - revision: The document's revision as read.
    ///   - nodes: The node ids read, in the order printed; truncated to ``nodeLimit``.
    ///   - scope: Whether the read covered the nodes alone or their subtrees.
    ///   - covered: How many nodes the read covered; defaults to the count of `nodes`
    ///     before truncation.
    public init(
        time: Date = Date(),
        identity: String,
        file: URL,
        verb: Verb,
        revision: String,
        nodes: [String],
        scope: Scope = .nodes,
        covered: Int? = nil
    ) {
        self.time = ActivityEvent.roundedToMilliseconds(time)
        self.identity = identity
        self.file = ActivityEvent.canonicalPath(for: file)
        self.verb = verb
        self.revision = revision
        self.nodes = Array(nodes.prefix(Self.nodeLimit))
        self.scope = scope
        self.covered = covered ?? nodes.count
    }

    /// When the read happened, to the millisecond.
    public var time: Date

    /// The reader's `--as` name. Never empty: an unattributed read is not logged.
    public var identity: String

    /// The absolute, canonical path of the document read.
    public var file: String

    /// The verb that read it.
    public var verb: Verb

    /// The document's revision as read.
    public var revision: String

    /// The node ids read, in the order printed, at most ``nodeLimit``.
    public var nodes: [String]

    /// Whether the read covered ``nodes`` alone or everything under them too.
    public var scope: Scope

    /// How many nodes the read covered, which may be more than ``nodes`` holds.
    public var covered: Int

    /// Whether this view already says everything `other` would: same reader, file and
    /// revision, every node of `other` among this one's, and no narrower scope.
    ///
    /// - Parameter other: A newer read.
    /// - Returns: `true` when recording `other` would add nothing.
    public func covers(_ other: ViewEvent) -> Bool {
        identity == other.identity
            && file == other.file
            && revision == other.revision
            && (scope == .subtrees || other.scope == .nodes)
            && Set(other.nodes).isSubset(of: nodes)
    }
}
