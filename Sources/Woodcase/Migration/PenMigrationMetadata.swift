//
//  PenMigrationMetadata.swift
//  Woodcase
//

import Foundation

/// Where a migration rule keeps a legacy value the current format cannot hold: the node's
/// `metadata.woodcase`, beside whatever metadata the node already has.
///
/// A rule also runs on the property patches of a `ref`'s `descendants`, and a patch's
/// `metadata` replaces the component node's whole metadata in that instance. So a patch
/// that writes no metadata of its own gets none: a key written there would wipe the
/// component's other metadata — its spans, its code-gen role — from the instance. The rule
/// reports such a value discarded instead.
enum PenMigrationMetadata {
    /// Writes `value` under `key` in the node's `metadata.woodcase`.
    ///
    /// - Parameters:
    ///   - value: The value to keep.
    ///   - key: The Woodcase key that holds it.
    ///   - node: The node's JSON object, or a descendant patch.
    /// - Returns: `false`, writing nothing, when `node` is a patch with no metadata of its
    ///   own (``isBarePatch(_:)``).
    static func keep(_ value: AnyCodable, as key: PenMetadata.WoodcaseKey, in node: inout [String: AnyCodable]) -> Bool {
        guard !isBarePatch(node) else { return false }
        let existing: [String: AnyCodable] = if case let .dictionary(object)? = node["metadata"] { object } else { [:] }
        var metadata = PenMetadata(object: existing)
        metadata[woodcase: key] = value
        node["metadata"] = .dictionary(metadata.object)
        return true
    }

    /// Whether `node` is a descendant patch — it has no `id`, which every node has — that
    /// writes no `metadata` of its own.
    static func isBarePatch(_ node: [String: AnyCodable]) -> Bool {
        node["id"] == nil && node["metadata"] == nil
    }

    /// The reason a value kept nowhere gives in its diagnostic.
    static let barePatchReason = "an instance override cannot hold it without replacing the component's metadata"

    /// A number in its stored form: an integer when whole.
    static func number(_ value: Double) -> AnyCodable {
        value.rounded() == value && abs(value) < 1e15 ? .int(Int(value)) : .double(value)
    }
}
