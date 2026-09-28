//
//  PenNodeOverlay.swift
//  Woodcase
//

import Foundation

/// A node's own keys with a patch laid over them, decoded as the merged JSON object
/// would be — without writing either one out as JSON.
///
/// An override is a JSON merge: a patch names keys of the node's own object, and the
/// merged object is decoded back into a node. That used to be done literally — encode
/// the node, decode it into a dictionary, lay the patch over, encode, decode — four coder
/// passes for every override applied, and in `woodcase-app.pen` they were most of what
/// a `set` cost (see <doc:WoodcasePerformance>).
///
/// The overlay runs the same decode over the same logical object without building it.
/// The node's top-level values are **captured**, not encoded: ``Capture`` records each
/// value the node's `encode(to:)` hands its keyed container, as the typed value it is. The
/// node's own `init(from:)` then reads this decoder, which answers a patched key from the
/// patch (decoded with ``AnyCodableDecoder``) and every other key with the captured value
/// itself, cast back to the type asked for. Because both halves are the node's own
/// `Codable` code, which keys exist, which become extras, root overrides or properties of
/// an unknown type, and what each decodes to are exactly what the round trip gave.
///
/// It declines — throws ``Unsupported`` — whenever it cannot answer a read without
/// encoding: a captured value asked for as another type, or through a nested container.
/// ``PenNodePatcher`` then takes the JSON round trip, so the overlay is never *wrong*,
/// only occasionally not faster. `PenNodePatcherEquivalenceTests` expands every fixture
/// with the overlay alone and requires the round trip's documents.
struct PenNodeOverlay: Decoder {
    /// The overlay could not answer a read without encoding the node.
    struct Unsupported: Error {}

    /// The node's top-level keys, as its `encode(to:)` wrote them.
    let captured: [String: Capture.Value]

    /// The patch, which wins over the node's own keys.
    let patch: [String: AnyCodable]

    var codingPath: [CodingKey] {
        []
    }

    /// Empty: the merge decoded in ``PenDecodingMode/file`` mode.
    var userInfo: [CodingUserInfoKey: Any] {
        [:]
    }

    /// The node the merged object decodes to.
    ///
    /// - Parameters:
    ///   - node: The node to patch. Its subtree is captured by reference, never encoded.
    ///   - patch: The keys to lay over the node's own.
    /// - Returns: The patched node.
    /// - Throws: ``Unsupported`` when the overlay cannot answer without encoding, or the
    ///   `DecodingError` a patch value raised.
    static func merged(_ node: PenNode, with patch: [String: AnyCodable]) throws -> PenNode {
        let capture = Capture()
        try node.encode(to: capture)
        guard !capture.storage.declined else { throw Unsupported() }
        return try PenNode(from: PenNodeOverlay(captured: capture.storage.values, patch: patch))
    }

    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(Keyed<Key>(captured: captured, patch: patch))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw Unsupported()
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw Unsupported()
    }
}

// MARK: - The merged object's container

extension PenNodeOverlay {
    /// The merged object: a patched key reads from the patch, any other from the node.
    struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
        /// The node's own keys.
        let captured: [String: Capture.Value]

        /// The patch.
        let patch: [String: AnyCodable]

        var codingPath: [CodingKey] {
            []
        }

        var allKeys: [Key] {
            var names = Set(captured.keys)
            names.formUnion(patch.keys)
            return names.compactMap { Key(stringValue: $0) }
        }

        func contains(_ key: Key) -> Bool {
            patch[key.stringValue] != nil || captured[key.stringValue] != nil
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            if let patched = patch[key.stringValue] { return patched == .null }
            switch captured[key.stringValue] {
            case .null: return true
            case .value: return false
            case nil: throw missing(key)
            }
        }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            try read(type, key)
        }

        /// The value under `key`: the patch's, decoded, or the node's own, as it was.
        ///
        /// Every `decode` overload lands here under a name of its own, so none of them
        /// can resolve back to itself.
        private func read<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
            if let patched = patch[key.stringValue] {
                return try AnyCodableDecoder.decode(type, from: patched, codingPath: [key])
            }
            switch captured[key.stringValue] {
            case let .value(value):
                // A top-level ``AnyCodable`` — an extra, a root override, a property of
                // an unknown type — comes back as the round trip's text would give it.
                if let raw = value as? AnyCodable, let normalized = AnyCodableDecoder.normalized(raw) as? T {
                    return normalized
                }
                guard let typed = value as? T else { throw Unsupported() }
                return typed
            case .null: throw Unsupported()
            case nil: throw missing(key)
            }
        }

        /// The error `JSONDecoder` gives a key the object does not hold.
        private func missing(_ key: Key) -> DecodingError {
            .keyNotFound(key, DecodingError.Context(
                codingPath: [],
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        /// The patch value under `key`; a captured value cannot be read as a container.
        private func patched(_ key: Key) throws -> AnyCodable {
            if let patched = patch[key.stringValue] { return patched }
            if captured[key.stringValue] != nil { throw Unsupported() }
            throw missing(key)
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            try read(type, key)
        }

        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            try read(type, key)
        }

        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            try read(type, key)
        }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            try read(type, key)
        }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            try read(type, key)
        }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            try read(type, key)
        }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            try read(type, key)
        }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            try read(type, key)
        }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            try read(type, key)
        }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            try read(type, key)
        }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            try read(type, key)
        }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            try read(type, key)
        }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            try read(type, key)
        }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            try read(type, key)
        }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type,
            forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try AnyCodableDecoder(patched(key), codingPath: [key]).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            try AnyCodableDecoder(patched(key), codingPath: [key]).unkeyedContainer()
        }

        func superDecoder() throws -> Decoder {
            throw Unsupported()
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            if let patched = patch[key.stringValue] { return AnyCodableDecoder(patched, codingPath: [key]) }
            if captured[key.stringValue] != nil { throw Unsupported() }
            return AnyCodableDecoder(.null, codingPath: [key])
        }
    }
}
