//
//  NodePropertyCodec+NaturalOverrides.swift
//  Woodcase
//

import Foundation

/// Where an instance override of a Woodcase-owned key is stored: in the override's own
/// `metadata.woodcase`, never under the raw key (rule 6; Ben's ruling, 2026-10-20).
///
/// A caller — or a file from before the rule, or a raw operation — may name the key the way
/// `override` names any other, `strokeDash=[4,2]` or `kind.strokeDash=[4,2]`. This is the one
/// place that turns those into the override's `metadata`, laid over what the entry already
/// keeps there, so the planner, ``EditOperation/normalized(in:)``, the document's apply, the
/// CRDT and decoding all store the same thing. The entry's `metadata` is then one whole value,
/// so undo restores it exactly, and expansion lays it over the component node's key by key
/// (``PenMetadata/overlaying(_:onto:)``).
public extension NodePropertyCodec {
    /// An override entry's writes with every Woodcase-owned key moved into its `metadata`.
    ///
    /// The spreads the entry's effects name move there too, as its own `shadowSpread`
    /// (`splittingOverrideSpreads(_:nodeID:)`).
    ///
    /// - Parameters:
    ///   - properties: The keys the write assigns, raw or as natural paths.
    ///   - unset: The keys the write removes, raw or as natural paths.
    ///   - existing: The override entry as it stands, whose `metadata` the keys join.
    /// - Returns: The same write with no Woodcase-owned key left outside `metadata`: a
    ///   `metadata` value holding the entry's keys laid over its current ones, or `metadata`
    ///   unset when nothing is left in it. A whole-node replacement (one with a `type`) is
    ///   returned as given; its node is decoded whole.
    static func foldingNaturalOverrideKeys(
        _ properties: [String: AnyCodable],
        unset: [String] = [],
        onto existing: [String: AnyCodable] = [:]
    ) -> (properties: [String: AnyCodable], unset: [String]) {
        guard properties[PenDescendantOverride.typeKey] == nil else { return (properties, unset) }
        // A spread its effects name is one more key of the override's metadata; a bad one is
        // refused by the planner before this (`splittingOverrideSpreads`), and kept here.
        let spreads: (properties: [String: AnyCodable], shadowSpread: AnyCodable?) =
            (try? splittingOverrideSpreads(properties, nodeID: "")) ?? (properties, nil)
        let properties = spreads.properties
        var writes = properties.compactMap { name, value in naturalOverrideKey(name).map { ($0, value) } }
        if let shadowSpread = spreads.shadowSpread { writes.append((.shadowSpread, shadowSpread)) }
        let removals = unset.compactMap(naturalOverrideKey)
        guard !writes.isEmpty || !removals.isEmpty else { return (properties, unset) }

        let metadataKey = rawKey(for: metadataPath)
        var metadata: [String: AnyCodable] = switch properties[metadataKey] ?? existing[metadataKey] {
        case let .dictionary(object)?: object
        default: [:]
        }
        var keys: [String: AnyCodable] = if case let .dictionary(object)? = metadata[PenMetadata.woodcaseNamespace] {
            object
        } else {
            [:]
        }
        for (key, value) in writes {
            keys[key.rawValue] = value // a null is kept: it clears the key on this instance
        }
        for key in removals {
            keys.removeValue(forKey: key.rawValue)
        }
        if keys.isEmpty {
            metadata.removeValue(forKey: PenMetadata.woodcaseNamespace)
        } else {
            metadata[PenMetadata.woodcaseNamespace] = .dictionary(keys)
        }

        var folded = properties.filter { name, _ in naturalOverrideKey(name) == nil }
        var remaining = unset.filter { naturalOverrideKey($0) == nil }
        let typeOnly = metadata.keys.allSatisfy { $0 == "type" }
            && (metadata["type"] == nil || metadata["type"] == .string(PenMetadata.woodcaseType))
        if typeOnly {
            folded.removeValue(forKey: metadataKey)
            if existing[metadataKey] != nil, !remaining.contains(metadataKey) { remaining.append(metadataKey) }
        } else {
            if metadata["type"] == nil { metadata["type"] = .string(PenMetadata.woodcaseType) }
            folded[metadataKey] = .dictionary(metadata)
            remaining.removeAll { $0 == metadataKey }
        }
        return (folded, remaining)
    }

    /// Whether a write or removal names a Woodcase-owned key an override stores in its
    /// metadata, by its raw field (`strokeDash`) or its natural path (`kind.strokeDash`).
    static func naturalOverrideKey(_ name: String) -> PenMetadata.WoodcaseKey? {
        PenMetadata.WoodcaseKey(naturalField: name) ?? PenMetadata.WoodcaseKey(naturalPath: name)
    }
}
