//
//  PenFileFollower+Start.swift
//  Woodcase
//

public extension PenFileFollower {
    /// Where a ``PenFileFollower`` begins.
    enum Start: Friendly {
        /// Now: only what happens after the follower is created.
        case end
        /// The whole retained log, delivered as ``Event/activity(_:)`` before anything new.
        case beginning
        /// Just after a position an earlier iterator reported (``Iterator/position``).
        /// Rows since then are delivered as ``Event/activity(_:)``: their writes happened
        /// while nobody was watching.
        case position(Position)
    }
}
