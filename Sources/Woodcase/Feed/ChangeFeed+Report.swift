//
//  ChangeFeed+Report.swift
//  Woodcase
//

import Foundation

public extension ChangeFeed {
    /// What one read of a feed found.
    ///
    /// Its JSON is what `woodcase changes --json` prints; the cursors are written as
    /// their ``ActivityCursor/token``s, the form `--since` takes back:
    ///
    /// ```json
    /// {"changes":[…],"cursor":"1a2b3c-40960","file":"/Users/ben/Designs/home.pen",
    ///  "identity":"claude","origin":"stored","restarted":false,
    ///  "revision":"3f2a91c0d4e5b678","since":"1a2b3c-38211","unlogged":null}
    /// ```
    struct Report: Friendly {
        /// Creates a report.
        ///
        /// - Parameters:
        ///   - file: The canonical path of the .pen file.
        ///   - identity: Who looked.
        ///   - revision: The document's revision when it was read.
        ///   - since: Where the read started.
        ///   - cursor: Where the next read should start.
        ///   - origin: Where ``since`` came from.
        ///   - restarted: Whether the start had been rotated away, so rows may be missing.
        ///   - unlogged: The file's divergence from the log, or `nil` when the log
        ///     explains it.
        ///   - changes: The rows, oldest first.
        public init(
            file: String,
            identity: String,
            revision: String,
            since: ActivityCursor,
            cursor: ActivityCursor,
            origin: Origin,
            restarted: Bool = false,
            unlogged: Unlogged? = nil,
            changes: [ActivityChangeSummary] = []
        ) {
            self.file = file
            self.identity = identity
            self.revision = revision
            self.since = since
            self.cursor = cursor
            self.origin = origin
            self.restarted = restarted
            self.unlogged = unlogged
            self.changes = changes
        }

        /// Where a report's start came from.
        public enum Origin: String, Friendly {
            /// The identity's stored cursor.
            case stored
            /// A cursor the caller passed (`--since`).
            case given = "since"
            /// No cursor was stored: the read started at the log's end.
            case firstLook = "first-look"
        }

        /// A file rewritten behind the log's back.
        public struct Unlogged: Friendly {
            /// Creates a divergence.
            ///
            /// - Parameters:
            ///   - since: The revision the newest logged row left the file at.
            ///   - found: The revision the file holds now.
            public init(since: String, found: String) {
                self.since = since
                self.found = found
            }

            /// The revision the newest logged row left the file at.
            public var since: String

            /// The revision the file holds now.
            public var found: String
        }

        /// The canonical path of the .pen file.
        public var file: String

        /// Who looked.
        public var identity: String

        /// The document's revision when it was read.
        public var revision: String

        /// Where the read started.
        public var since: ActivityCursor

        /// Where the next read should start: past every row read, listed or not.
        public var cursor: ActivityCursor

        /// Where ``since`` came from.
        public var origin: Origin

        /// Whether the start had been rotated out of the retained log, so rows between
        /// it and the oldest retained row are missing.
        public var restarted: Bool

        /// The file's divergence from the log, or `nil` when the log explains the file.
        public var unlogged: Unlogged?

        /// The rows, oldest first.
        public var changes: [ActivityChangeSummary]

        /// Whether there is anything to act on: no rows and no unlogged change.
        public var isEmpty: Bool {
            changes.isEmpty && unlogged == nil
        }
    }
}
