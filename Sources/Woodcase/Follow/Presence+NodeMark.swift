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
        ///   - revision: The document revision after the change.
        ///   - time: When it happened.
        ///   - op: The verb, or `nil` when a batch mixed several.
        public init(
            nodes: [String],
            paths: [String],
            revision: String,
            time: Date,
            op: ActivityEvent.Kind? = nil
        ) {
            self.nodes = Array(nodes.prefix(Self.nodeLimit))
            self.paths = Array(paths.prefix(Self.nodeLimit))
            self.revision = revision
            self.time = time
            self.op = op
        }

        /// The node ids, subject first.
        public var nodes: [String]

        /// The name paths of ``nodes``, in the same order.
        public var paths: [String]

        /// The document revision after the change.
        public var revision: String

        /// When it happened — the newest event of a batch.
        public var time: Date

        /// The verb every event of the batch shared, or `nil` when they differed.
        public var op: ActivityEvent.Kind?
    }
}
