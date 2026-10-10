//
//  PenFileFollower+Event.swift
//  Woodcase
//

public extension PenFileFollower {
    /// One thing that happened to the followed document.
    enum Event: Friendly {
        /// The file changed, with the rows that explain it — none for a write no tool
        /// logged.
        case changed(FileChange)

        /// A row whose change the follower did not see: history from before it started,
        /// or a row that arrived after its change was delivered unattributed.
        case activity(ActivityEvent)

        /// Someone read nodes of the document through a woodcase read verb.
        case viewed(ViewEvent)

        /// The log was rotated past the follower's cursor and the rows in between are
        /// gone; what follows starts over from the live log.
        case restarted

        /// The change, if this is ``changed(_:)``.
        public var change: FileChange? {
            if case let .changed(change) = self { change } else { nil }
        }

        /// The read, if this is ``viewed(_:)``.
        public var view: ViewEvent? {
            if case let .viewed(view) = self { view } else { nil }
        }

        /// The row, if this is ``activity(_:)``.
        public var activity: ActivityEvent? {
            if case let .activity(event) = self { event } else { nil }
        }
    }
}
