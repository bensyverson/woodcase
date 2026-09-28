//
//  VectorClock+Consensus.swift
//  Woodcase
//

import Foundation

public extension VectorClock {
    /// Computes the component-wise minimum across all clocks.
    ///
    /// The result represents the state that **all** peers have acknowledged.
    /// For each peer, the minimum time across all clocks is kept. A peer
    /// missing from any clock is treated as having time 0, which floors
    /// that peer's entry to 0.
    ///
    /// - Parameter clocks: The vector clocks to compare.
    /// - Returns: A clock whose entries are the per-peer minimums, or an
    ///   empty clock if the array is empty.
    static func minimum(of clocks: [VectorClock]) -> VectorClock {
        guard let first = clocks.first else { return VectorClock() }
        guard clocks.count > 1 else { return first }

        // Collect all known peers across all clocks
        var allPeers = Set<PeerID>()
        for clock in clocks {
            allPeers.formUnion(clock.entries.keys)
        }

        var result = VectorClock()
        for peerID in allPeers {
            var minTime: UInt64 = .max
            for clock in clocks {
                let t = clock.time(for: peerID)
                if t < minTime {
                    minTime = t
                }
            }
            if minTime > 0 {
                result.entries[peerID] = minTime
            }
        }
        return result
    }
}
