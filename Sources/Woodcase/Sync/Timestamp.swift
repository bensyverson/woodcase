//
//  Timestamp.swift
//  Woodcase
//

import Foundation

/// A unique, totally-ordered timestamp combining a Lamport clock value with a peer ID.
///
/// Timestamps provide a total order across all operations from all peers:
/// 1. Compare by ``time`` (higher time = later)
/// 2. Break ties by ``peerID`` (lexicographic comparison)
///
/// This guarantees that no two distinct operations ever share the same timestamp,
/// which is essential for deterministic CRDT conflict resolution.
public struct Timestamp: Friendly, Comparable {
    /// The Lamport clock value at the time this timestamp was created.
    public let time: UInt64

    /// The peer that created this timestamp.
    public let peerID: PeerID

    /// Creates a timestamp with the given time and peer ID.
    ///
    /// - Parameters:
    ///   - time: The Lamport clock value.
    ///   - peerID: The originating peer's identifier.
    public init(time: UInt64, peerID: PeerID) {
        self.time = time
        self.peerID = peerID
    }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        if lhs.time != rhs.time {
            return lhs.time < rhs.time
        }
        return lhs.peerID < rhs.peerID
    }
}
