//
//  VectorClock+Coverage.swift
//  Woodcase
//

import Foundation

public extension VectorClock {
    /// Notes that the operation with this id has been applied, raising its peer's entry
    /// to the id's time if it was lower.
    ///
    /// - Parameter id: The applied operation's id.
    mutating func record(_ id: Timestamp) {
        entries[id.peerID] = max(time(for: id.peerID), id.time)
    }

    /// Whether the operation with this id is reflected in this clock: its peer's entry
    /// has reached the id's time.
    ///
    /// - Parameter id: An operation's id.
    /// - Returns: `true` when this clock's entry for the id's peer is at least its time.
    func covers(_ id: Timestamp) -> Bool {
        time(for: id.peerID) >= id.time
    }
}
