//
//  PeerID.swift
//  Woodcase
//

import Foundation

/// A unique identifier for a peer in a collaborative editing session.
///
/// Each peer (user/device) gets a unique `PeerID` when joining collaborative mode.
/// Peer IDs are used for tie-breaking in CRDT conflict resolution — when two
/// operations have the same Lamport timestamp, the higher peer ID wins.
///
/// Wraps a UUID string for guaranteed uniqueness.
public struct PeerID: Friendly, Comparable {
    /// The underlying string identifier.
    public let rawValue: String

    /// Creates a peer ID from a raw string value.
    ///
    /// - Parameter rawValue: The string identifier for this peer.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Generates a new unique peer ID using a UUID.
    ///
    /// - Returns: A fresh peer ID guaranteed to be unique.
    public static func generate() -> PeerID {
        PeerID(rawValue: UUID().uuidString)
    }

    /// A well-known peer ID used for initial document state.
    ///
    /// All peers use this ID when building the initial RGA lists and tree state
    /// from a ``PenDocument``. This ensures that position IDs for the initial
    /// document are identical across all replicas, allowing cross-peer
    /// references (e.g. list deletes) to work correctly.
    public static let genesis = PeerID(rawValue: "__genesis__")

    public static func < (lhs: PeerID, rhs: PeerID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
