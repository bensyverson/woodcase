//
//  VectorClock.swift
//  Woodcase
//

import Foundation

/// A vector clock tracking the latest known time for each peer.
///
/// Used to determine causal ordering between operations from different peers.
/// A vector clock *dominates* another when it has seen at least as much from
/// every peer, which means all operations reflected in the dominated clock
/// are also reflected in the dominating one.
///
/// ``CRDTDocument`` uses vector clocks for dependency tracking and
/// operation log truncation.
public struct VectorClock: Friendly {
    /// The per-peer time entries.
    public var entries: [PeerID: UInt64]

    /// Creates an empty vector clock.
    public init() {
        entries = [:]
    }

    /// Returns the time for the given peer, or 0 if unknown.
    ///
    /// - Parameter peerID: The peer to query.
    /// - Returns: The latest known time for that peer.
    public func time(for peerID: PeerID) -> UInt64 {
        entries[peerID] ?? 0
    }

    /// Increments the entry for the given peer by one.
    ///
    /// - Parameter peerID: The peer whose time to advance.
    public mutating func increment(for peerID: PeerID) {
        entries[peerID] = (entries[peerID] ?? 0) + 1
    }

    /// Returns `true` if this clock dominates `other`.
    ///
    /// A clock dominates another when every peer's entry is greater than or
    /// equal to the corresponding entry in the other clock. This means all
    /// events captured by `other` are also captured by `self`.
    ///
    /// - Parameter other: The clock to compare against.
    /// - Returns: `true` if `self` has seen at least as much as `other`.
    public func dominates(_ other: VectorClock) -> Bool {
        for (peerID, otherTime) in other.entries {
            if time(for: peerID) < otherTime {
                return false
            }
        }
        return true
    }

    /// Merges another vector clock into this one, taking the component-wise maximum.
    ///
    /// After merging, this clock reflects the combined knowledge of both clocks.
    ///
    /// - Parameter other: The clock to merge in.
    public mutating func merge(_ other: VectorClock) {
        for (peerID, otherTime) in other.entries {
            entries[peerID] = max(entries[peerID] ?? 0, otherTime)
        }
    }
}
