//
//  PenLayoutStats.swift
//  Woodcase
//

import Foundation

/// What one layout pass did: which containers it laid out, how many leaves it sized, and
/// how often it skipped a subtree on a remembered size.
///
/// It is the evidence for the node-granular contract — after one node is resized, the
/// containers laid out are its ancestors plus the descendants whose offered space changed
/// — and the first thing to read when an incremental layout is slower than it should be.
public struct PenLayoutStats: Friendly {
    /// The containers laid out, by expanded id, in the order they finished; a container
    /// laid out more than once in a pass is listed each time.
    public var containersLaidOut: [String] = []

    /// How many leaves were sized: text measured, or declared sizes resolved.
    public var leavesSized = 0

    /// How many calls took a remembered size and skipped their subtree.
    public var hits = 0

    /// Empty statistics.
    public init() {}
}
