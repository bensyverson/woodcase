//
//  LamportClock.swift
//  Woodcase
//

import Foundation

/// A Lamport logical clock for establishing causal ordering of events.
///
/// Each tick produces a monotonically increasing timestamp. When a remote
/// timestamp is witnessed, the clock advances past it to maintain the
/// "happened-before" guarantee.
///
/// Used internally by ``CRDTDocument`` to generate ``Timestamp`` values
/// for CRDT operations.
public struct LamportClock: Friendly, Comparable {
    /// The current logical time.
    public private(set) var time: UInt64

    /// Creates a clock starting at zero.
    public init() {
        time = 0
    }

    /// Advances the clock by one and returns the new time.
    ///
    /// - Returns: The new logical time after incrementing.
    @discardableResult
    public mutating func tick() -> UInt64 {
        time += 1
        return time
    }

    /// Advances the clock past the given remote time.
    ///
    /// Sets the local time to `max(local, remote) + 1`, ensuring this clock
    /// will produce timestamps strictly after the witnessed event.
    ///
    /// - Parameter remote: The remote timestamp to incorporate.
    public mutating func witness(_ remote: UInt64) {
        time = max(time, remote) + 1
    }

    public static func < (lhs: LamportClock, rhs: LamportClock) -> Bool {
        lhs.time < rhs.time
    }
}
