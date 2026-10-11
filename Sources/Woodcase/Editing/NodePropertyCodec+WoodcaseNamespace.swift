//
//  NodePropertyCodec+WoodcaseNamespace.swift
//  Woodcase
//

import Foundation

/// An authored metadata write stores Woodcase's keys under `metadata.woodcase` only.
///
/// A file written before the namespace keeps its old spellings (`_role`, a post-it's
/// bare `state`), and they are still read. An agent's write converts what it touches:
/// a key written in the namespace removes its old spelling, and a key written under its
/// old spelling lands in the namespace instead. Keys the write leaves alone stay as the
/// file has them, so a write never rewrites more of the object than it names. See
/// <doc:PenMetadataNamespace>.
///
/// ``folding(_:onto:)`` applies this to a `set`'s metadata, and the batch planner to
/// every node of an `add` or `replace` subtree, before the authoring check sees them.
public extension NodePropertyCodec {
    /// A metadata write with every Woodcase key it changes stored under the namespace.
    ///
    /// - Parameters:
    ///   - written: The whole metadata object as it will be written.
    ///   - current: The metadata the node holds now, or `nil` for a node being created;
    ///     a key whose old spelling still holds the current value was not written.
    /// - Returns: The object to write, with `type` ``PenMetadata/woodcaseType`` when it
    ///   had none — Pen's schema requires one — or `nil` when it holds nothing but that
    ///   type, which is no metadata at all.
    static func storingWoodcaseKeysInNamespace(
        _ written: [String: AnyCodable],
        replacing current: PenMetadata?
    ) -> [String: AnyCodable]? {
        let before = current ?? PenMetadata(type: nil)
        var result = PenMetadata(object: written)
        // The type goes last: while it stands, it is what makes the bare note keys read.
        let keys = PenMetadata.WoodcaseKey.allCases.filter { $0 != .type } + [.type]
        for key in keys {
            guard let old = result.oldStyleValue(of: key) else { continue }
            if result.namespacedValue(of: key) != before.namespacedValue(of: key) {
                result[woodcase: key] = result.namespacedValue(of: key)
            } else if old != before.oldStyleValue(of: key) {
                result[woodcase: key] = old
            }
        }
        return result.typedForWriting()?.object
    }

    /// Deep-key writes into metadata, aimed at the namespace.
    ///
    /// A write to an old spelling (`common.metadata._props.label`, a post-it's bare
    /// `state`) is aimed at its namespaced key instead, and a key written into the
    /// namespace whose value still lives under its old spelling is moved in first, so a
    /// write of one entry inside `woodcase.props` merges with the declared parameters
    /// rather than starting a new map beside them.
    ///
    /// - Parameters:
    ///   - writes: The deep-key writes, each a key path inside the metadata object.
    ///   - object: The metadata object the writes merge onto.
    /// - Returns: The object, with every written key's old spelling moved in, and the
    ///   writes, aimed at the namespace.
    internal static func aimingAtWoodcaseNamespace(
        _ writes: [(keyPath: [String], value: AnyCodable)],
        onto object: [String: AnyCodable]
    ) -> (object: [String: AnyCodable], writes: [(keyPath: [String], value: AnyCodable)]) {
        var metadata = PenMetadata(object: object)
        let aimed = writes.map { write -> (keyPath: [String], value: AnyCodable) in
            guard let head = write.keyPath.first, let key = metadata.woodcaseKey(forOldSpelling: head) else {
                return write
            }
            return ([PenMetadata.woodcaseNamespace, key.rawValue] + write.keyPath.dropFirst(), write.value)
        }
        for write in aimed where write.keyPath.first == PenMetadata.woodcaseNamespace && write.keyPath.count > 2 {
            guard let key = PenMetadata.WoodcaseKey(rawValue: write.keyPath[1]),
                  metadata.namespacedValue(of: key) == nil,
                  let old = metadata.oldStyleValue(of: key)
            else { continue }
            metadata[woodcase: key] = old
        }
        return (metadata.object, aimed)
    }

    /// A subtree about to be inserted, with every node's metadata stored as
    /// ``storingWoodcaseKeysInNamespace(_:replacing:)`` stores it.
    ///
    /// - Parameters:
    ///   - subtree: The subtree, with its ids settled.
    ///   - current: The node each id names now, for a `replace`; an `add` passes a
    ///     lookup that finds nothing, so every old spelling it carries moves in.
    /// - Returns: The subtree to insert.
    static func storingWoodcaseKeysInNamespace(in subtree: PenNode, current: (String) -> PenNode?) -> PenNode {
        let rewritten = PenTreeRewrite.rewrite([subtree], context: ()) { node, _ in
            guard let metadata = node.common.metadata,
                  metadata.type == nil || !metadata.oldStyleWoodcaseKeys.isEmpty
            else {
                return .descend(node, ())
            }
            var stored = node
            stored.common.metadata = storingWoodcaseKeysInNamespace(
                metadata.object, replacing: current(node.id)?.common.metadata
            ).map(PenMetadata.init(object:))
            return .descend(stored, ())
        }
        return rewritten.first ?? subtree
    }
}
