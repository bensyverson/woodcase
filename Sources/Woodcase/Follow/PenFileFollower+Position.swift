//
//  PenFileFollower+Position.swift
//  Woodcase
//

public extension PenFileFollower {
    /// How far a follower has read, in a form that survives log rotation and can be
    /// stored and handed back as ``Start/position(_:)``.
    struct Position: Friendly {
        /// Creates a position.
        ///
        /// - Parameters:
        ///   - activity: Where the next activity-log read starts.
        ///   - views: Where the next view-log read starts.
        public init(activity: ActivityCursor, views: ActivityCursor = .start) {
            self.activity = activity
            self.views = views
        }

        /// Where the next activity-log read starts.
        public var activity: ActivityCursor

        /// Where the next view-log read starts.
        public var views: ActivityCursor
    }
}
