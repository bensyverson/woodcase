//
//  PenFileFollower+Start.swift
//  Woodcase
//

import Foundation

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
        /// The rows and reads stamped at or after a moment, delivered as ``beginning``
        /// delivers them — every row as ``Event/activity(_:)``, then every read as
        /// ``Event/viewed(_:)``, each in log order — and then everything new, exactly as
        /// ``end`` delivers it.
        ///
        /// The cost is the window's, not the history's: each log is walked backward from
        /// its end, and a rotated archive is opened only when the window reaches past the
        /// live file's first row. The history ends where the logs ended when the follower
        /// was made — as ``end`` is resolved then — so a write after that arrives live,
        /// matched with its change, and nothing at the seam is lost or delivered twice.
        ///
        /// Rows are appended in time order only up to the instant between a writer stamping
        /// a row and taking the log's lock, so the walk steps past rows a few seconds older
        /// than the date before it stops: a window row filed behind one of them is still
        /// delivered, and the older row is not.
        case since(Date)
    }
}
