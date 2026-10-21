//
//  PenMigrationMetadata.swift
//  Woodcase
//

import Foundation

/// Where a migration rule keeps a legacy value the current format cannot hold: the node's
/// `metadata.woodcase`, beside whatever metadata the node already has.
///
/// A rule also runs on the property patches of a `ref`'s `descendants`. A patch's
/// `metadata.woodcase` is laid over the component node's key by key on expansion (rule 6,
/// ``PenMetadata/overlaying(_:onto:)``), so a key written into a patch with no metadata of
/// its own wipes nothing else from the instance, and is kept like any other. Before rule 6 a
/// patch's `metadata` replaced the component node's whole metadata, and such values were
/// discarded.
enum PenMigrationMetadata {
    /// Writes `value` under `key` in the node's `metadata.woodcase`; metadata the write
    /// creates is typed ``PenMetadata/woodcaseType``, as every write Woodcase makes is.
    ///
    /// - Parameters:
    ///   - value: The value to keep.
    ///   - key: The Woodcase key that holds it.
    ///   - node: The node's JSON object, or a descendant patch.
    static func keep(_ value: AnyCodable, as key: PenMetadata.WoodcaseKey, in node: inout [String: AnyCodable]) {
        let existing: [String: AnyCodable] = if case let .dictionary(object)? = node["metadata"] { object } else { [:] }
        var metadata = PenMetadata(object: existing)
        if metadata.type == nil { metadata.type = PenMetadata.woodcaseType }
        metadata[woodcase: key] = value
        node["metadata"] = .dictionary(metadata.object)
    }

    /// A number in its stored form: an integer when whole.
    static func number(_ value: Double) -> AnyCodable {
        value.rounded() == value && abs(value) < 1e15 ? .int(Int(value)) : .double(value)
    }
}
