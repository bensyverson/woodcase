//
//  PropertyDiff+Extras.swift
//  Woodcase
//

import Foundation

public extension PropertyDiff {
    /// Compares two nodes' extras and returns the `"extras.<key>"` path of every key
    /// that was added, removed or changed.
    ///
    /// The paths are the ones ``EditOperation/setProperties(_:)`` writes through
    /// ``NodePropertyCodec`` — a removed key is set to ``AnyCodable/null`` — so a diff of
    /// two nodes turns into a patch key for key.
    ///
    /// - Parameters:
    ///   - old: The previous extras.
    ///   - new: The updated extras.
    /// - Returns: The paths of the keys that differ.
    static func diffExtras(old: PenExtras, new: PenExtras) -> Set<String> {
        var changed = Set<String>()
        for key in Set(old.values.keys).union(new.values.keys) where old[key] != new[key] {
            changed.insert(NodePropertyCodec.extrasPrefix + key)
        }
        return changed
    }
}
