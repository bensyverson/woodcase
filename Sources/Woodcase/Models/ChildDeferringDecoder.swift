//
//  ChildDeferringDecoder.swift
//  Woodcase
//

import Foundation

/// A decoder that decodes a container node's payload without its `children`.
///
/// A payload's synthesized `init(from:)` decodes `children` as `[PenNode]`, and each of
/// those decodes its own children in turn, so the decode of a tree nests as deep as the
/// tree — and a debug build reserves kilobytes a level for it (`FrameData`'s decoder
/// alone is 7.7 KB). Handed this wrapper instead, the payload finds an empty array
/// under `children` and the real one is set aside in ``children``, for
/// ``PenNode/init(from:)`` to decode from a work list after the payload's frame has
/// returned. Everything else is the wrapped decoder's. See
/// `project/2026-09-26-debug-stack-depth.md`.
struct ChildDeferringDecoder: Decoder {
    /// The decoder the payload would otherwise have been given.
    let base: Decoder

    /// Where the set-aside `children` land.
    private let deferred = Deferred()

    /// The decoder positioned on the payload's `children` array, or `nil` when the
    /// payload has none — the key absent or `null`.
    var children: Decoder? {
        deferred.decoder
    }

    /// Wraps a node object's decoder.
    ///
    /// - Parameter base: The decoder to read from.
    init(_ base: Decoder) {
        self.base = base
    }

    var codingPath: [CodingKey] {
        base.codingPath
    }

    var userInfo: [CodingUserInfoKey: Any] {
        base.userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        try KeyedDecodingContainer(Container(base: base.container(keyedBy: type), deferred: deferred))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        try base.unkeyedContainer()
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        try base.singleValueContainer()
    }

    /// The set-aside `children`, shared by every container the wrapper hands out.
    private final class Deferred {
        var decoder: Decoder?
    }

    /// The payload's keyed container: the wrapped one, except that `children` reads
    /// as empty and is set aside.
    private struct Container<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let base: KeyedDecodingContainer<Key>
        let deferred: Deferred

        /// The key a container node's payload keeps its children under.
        private static var childrenKey: String {
            "children"
        }

        var codingPath: [CodingKey] {
            base.codingPath
        }

        var allKeys: [Key] {
            base.allKeys
        }

        func contains(_ key: Key) -> Bool {
            base.contains(key)
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            try base.decodeNil(forKey: key)
        }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            guard let empty = try setAside(type, forKey: key) else {
                return try base.decode(type, forKey: key)
            }
            return empty
        }

        func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
            guard Self.defers(type, key) else { return try base.decodeIfPresent(type, forKey: key) }
            guard base.contains(key), try !base.decodeNil(forKey: key) else { return nil }
            return try setAside(type, forKey: key)
        }

        /// Sets the children aside and answers an empty array in their place, or `nil`
        /// for any other key.
        private func setAside<T>(_ type: T.Type, forKey key: Key) throws -> T? {
            guard Self.defers(type, key) else { return nil }
            deferred.decoder = try base.superDecoder(forKey: key)
            return [PenNode]() as? T
        }

        /// Whether this is the read of a node's children.
        private static func defers(_ type: (some Any).Type, _ key: Key) -> Bool {
            key.stringValue == childrenKey && type == [PenNode].self
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            try base.decode(type, forKey: key)
        }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            try base.decode(type, forKey: key)
        }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type,
            forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try base.nestedContainer(keyedBy: type, forKey: key)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            try base.nestedUnkeyedContainer(forKey: key)
        }

        func superDecoder() throws -> Decoder {
            try base.superDecoder()
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            try base.superDecoder(forKey: key)
        }
    }
}
