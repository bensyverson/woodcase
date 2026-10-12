//
//  NodePropertyCodec+DeepRead.swift
//  Woodcase
//

import Foundation

/// Reading *one key* of a whole-object property — the read side of
/// ``NodePropertyCodec/folding(_:onto:)``, so `tree --props common.metadata.woodcase.author`
/// reads the same key `set common.metadata.woodcase.author=ana` writes.
///
/// Inside `common.metadata`, a key Woodcase owns reads the way Woodcase reads it
/// (``PenMetadata/subscript(woodcase:)``): `woodcase.leaf` answers from an old-style
/// post-it's bare `leaf` too, and an old spelling such as `leaf` or `_props` reads the
/// namespaced value wherever a write to it would land in the namespace. Any other key is
/// read as the file has it. A key that is absent reads as ``AnyCodable/null``, the same
/// answer as any unset property — the path *is* a property, it just holds nothing.
///
/// ```swift
/// try NodePropertyCodec.value(at: "common.metadata.woodcase.author", of: note) // .string("ana")
/// try NodePropertyCodec.value(at: "common.metadata.woodcase.tint", of: plain)  // .null
/// ```
extension NodePropertyCodec {
    /// Reads a deep key inside a whole-object property.
    ///
    /// - Parameters:
    ///   - property: The whole-object property, from ``deepKeyedPaths``.
    ///   - keyPath: The keys to walk inside it.
    ///   - node: The node to read from.
    /// - Returns: The value at the key path, or ``AnyCodable/null`` when any key on the
    ///   way is absent or not an object.
    public static func deepValue(in property: String, at keyPath: [String], of node: PenNode) throws -> AnyCodable {
        guard property == metadataPath else {
            return try walk(value(at: property, of: node), along: keyPath)
        }
        let metadata = node.common.metadata ?? PenMetadata(type: nil)
        guard let head = keyPath.first else { return .null }
        if head == PenMetadata.woodcaseNamespace, keyPath.count > 1,
           let key = PenMetadata.WoodcaseKey(rawValue: keyPath[1])
        {
            return walk(metadata[woodcase: key] ?? .null, along: Array(keyPath.dropFirst(2)))
        }
        if let key = metadata.woodcaseKey(forOldSpelling: head) {
            return walk(metadata[woodcase: key] ?? .null, along: Array(keyPath.dropFirst()))
        }
        return walk(metadata[head] ?? .null, along: Array(keyPath.dropFirst()))
    }

    /// Walks a key path down through nested objects.
    private static func walk(_ value: AnyCodable, along keyPath: [String]) -> AnyCodable {
        var current = value
        for key in keyPath {
            guard case let .dictionary(object) = current, let next = object[key] else { return .null }
            current = next
        }
        return current
    }
}
