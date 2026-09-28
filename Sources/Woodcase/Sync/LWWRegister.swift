//
//  LWWRegister.swift
//  Woodcase
//

import Foundation

/// A Last-Writer-Wins register for conflict-free replicated state.
///
/// Stores a single value with a ``Timestamp``. When two peers write different
/// values concurrently, the write with the higher timestamp wins. Ties are
/// broken by ``PeerID`` comparison, ensuring deterministic convergence.
///
/// ## Usage
///
/// ```swift
/// var reg = LWWRegister(value: "hello", timestamp: ts1)
/// reg.set("world", at: ts2) // returns true if ts2 > ts1
/// ```
public struct LWWRegister<Value: Friendly>: Friendly {
    /// The current value of the register.
    public private(set) var value: Value

    /// The timestamp of the last accepted write.
    public private(set) var timestamp: Timestamp

    /// Creates a register with an initial value and timestamp.
    ///
    /// - Parameters:
    ///   - value: The initial value.
    ///   - timestamp: The timestamp of the initial write.
    public init(value: Value, timestamp: Timestamp) {
        self.value = value
        self.timestamp = timestamp
    }

    /// Attempts to set a new value at the given timestamp.
    ///
    /// The write succeeds only if `newTimestamp` is strictly greater than
    /// the current timestamp. Equal timestamps are treated as no-ops to
    /// ensure idempotency.
    ///
    /// - Parameters:
    ///   - newValue: The value to write.
    ///   - newTimestamp: The timestamp of this write.
    /// - Returns: `true` if the write was accepted, `false` if it was stale.
    @discardableResult
    public mutating func set(_ newValue: Value, at newTimestamp: Timestamp) -> Bool {
        if newTimestamp > timestamp {
            value = newValue
            timestamp = newTimestamp
            return true
        }
        return false
    }
}
