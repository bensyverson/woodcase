//
//  PenFileFollower+FileChange.swift
//  Woodcase
//

import Foundation

public extension PenFileFollower {
    /// One settled change to the followed file and the log rows that explain it.
    struct FileChange: Friendly {
        /// Creates a change.
        ///
        /// - Parameters:
        ///   - events: The rows that explain it, in log order; empty when none arrived.
        ///   - changedAt: When the change was noticed.
        public init(events: [ActivityEvent], changedAt: Date) {
            self.events = events
            self.changedAt = changedAt
        }

        /// The rows that explain the change, in log order; empty when no tool logged it
        /// within the window.
        public var events: [ActivityEvent]

        /// When the change was noticed.
        public var changedAt: Date

        /// Whether any row explained the change.
        public var isAttributed: Bool {
            !events.isEmpty
        }

        /// The document revision after the change: the newest row's, or `nil` when the
        /// change is unattributed and the follower — which does not parse the file —
        /// cannot say.
        public var revision: String? {
            events.last?.revision
        }

        /// Every node the rows touched, in order of first mention.
        public var nodes: [String] {
            var seen: Set<String> = []
            return events.flatMap(\.nodes).filter { seen.insert($0).inserted }
        }

        /// The writers, in order of first appearance.
        public var identities: [String] {
            var seen: Set<String> = []
            return events.map(\.identity).filter { seen.insert($0).inserted }
        }
    }
}
