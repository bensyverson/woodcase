//
//  Presence+NodeMark.swift
//  Woodcase
//

import Foundation

public extension Presence {
    /// The nodes one change (a whole batch) or one read touched.
    struct NodeMark: Friendly {
        /// The most nodes a mark keeps. A batch that touches more is cut off here, with
        /// the subject — the first node — always kept.
        public static let nodeLimit = 32

        /// Creates a mark.
        ///
        /// - Parameters:
        ///   - nodes: The node ids, subject first; truncated to ``nodeLimit``.
        ///   - paths: Their name paths, in the same order; truncated the same way.
        ///   - revision: The document revision after the change, or as read.
        ///   - time: When it happened.
        ///   - op: The write's verb, or `nil` when a batch mixed several, or for a read.
        ///   - verb: The read verb, for a mark made from a ``ViewEvent``; `nil` for a write.
        public init(
            nodes: [String],
            paths: [String],
            revision: String,
            time: Date,
            op: ActivityEvent.Kind? = nil,
            verb: ViewEvent.Verb? = nil
        ) {
            self.nodes = Array(nodes.prefix(Self.nodeLimit))
            self.paths = Array(paths.prefix(Self.nodeLimit))
            self.revision = revision
            self.time = time
            self.op = op
            self.verb = verb
        }

        /// The node ids, subject first.
        public var nodes: [String]

        /// The name paths of ``nodes``, in the same order; empty for a read, which logs
        /// ids only.
        public var paths: [String]

        /// The document revision after the change.
        public var revision: String

        /// When it happened — the newest event of a batch.
        public var time: Date

        /// The verb every event of the batch shared, or `nil` when they differed or the
        /// mark is a read.
        public var op: ActivityEvent.Kind?

        /// The read verb behind a view mark; `nil` for a change.
        public var verb: ViewEvent.Verb?
    }
}
