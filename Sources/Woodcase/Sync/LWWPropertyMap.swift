//
//  LWWPropertyMap.swift
//  Woodcase
//

import Foundation

/// Per-property timestamp tracking for a node's fields.
///
/// Each property path (e.g. `"common.name"`, `"kind.width"`) is independently
/// tracked with its own ``Timestamp``. This enables fine-grained LWW conflict
/// resolution: two peers can edit different properties of the same node
/// concurrently without either edit being lost.
///
/// ## Usage
///
/// ```swift
/// var map = LWWPropertyMap()
/// if map.shouldAccept(property: "common.name", at: remoteTimestamp) {
///     // Apply the remote value
///     map.record(property: "common.name", at: remoteTimestamp)
/// }
/// ```
public struct LWWPropertyMap: Friendly {
    /// Maps property path strings to the timestamp of the last accepted write.
    private(set) var timestamps: [String: Timestamp]

    /// Creates an empty property map.
    public init() {
        timestamps = [:]
    }

    /// Returns whether a write to the given property at the given timestamp
    /// should be accepted (i.e., the timestamp is newer than any previous write).
    ///
    /// - Parameters:
    ///   - property: The property path (e.g. `"common.name"`).
    ///   - timestamp: The proposed write's timestamp.
    /// - Returns: `true` if the write should be accepted.
    public func shouldAccept(property: String, at timestamp: Timestamp) -> Bool {
        guard let existing = timestamps[property] else { return true }
        return timestamp > existing
    }

    /// Records that a property was written at the given timestamp.
    ///
    /// - Parameters:
    ///   - property: The property path.
    ///   - timestamp: The write's timestamp.
    public mutating func record(property: String, at timestamp: Timestamp) {
        timestamps[property] = timestamp
    }
}
