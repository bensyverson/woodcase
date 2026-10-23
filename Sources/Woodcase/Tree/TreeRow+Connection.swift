//
//  TreeRow+Connection.swift
//  Woodcase
//

import Foundation

public extension TreeRow {
    /// What a row says about a connection: the two ends it joins.
    ///
    /// A connection's layout rect says nothing about it — it is drawn from where its ends
    /// are — so a listing names them instead: `tree` prints `[Start.bottom → Below.left]`
    /// after the name, and `tree --json` and `find` carry this.
    struct Connection: Friendly {
        /// Creates the summary.
        ///
        /// - Parameters:
        ///   - source: Where the connection starts.
        ///   - target: Where it ends.
        public init(source: End, target: End) {
            self.source = source
            self.target = target
        }

        /// Where the connection starts.
        public var source: End
        /// Where it ends.
        public var target: End

        /// One end: the node it names and the point on that node's box.
        public struct End: Friendly {
            /// Creates an end.
            ///
            /// - Parameters:
            ///   - path: The node's id, or an `instance/child` path.
            ///   - anchor: The anchor's spelling: `center`, `top`, `right`, `bottom` or `left`.
            ///   - name: The node's name, or `nil` when it has none or the document has no
            ///     such node.
            public init(path: String, anchor: String, name: String?) {
                self.path = path
                self.anchor = anchor
                self.name = name
            }

            /// The node's id, or an `instance/child` path, as the file writes it.
            public var path: String
            /// The anchor's spelling.
            public var anchor: String
            /// The node's name, or `nil`.
            public var name: String?
        }

        /// The ends as one line reads them: `Start.bottom → Below.left`.
        public var summary: String {
            "\(source.path).\(source.anchor) → \(target.path).\(target.anchor)"
        }
    }
}
