//
//  SingleKeyEncoder+KeyCapturingContainer.swift
//  Woodcase
//

import Foundation

extension SingleKeyEncoder {
    /// The payload's top-level keyed container: encodes the wanted key's value on its own
    /// and drops every other key unencoded.
    ///
    /// The value is encoded the way `JSONEncoder` would encode it inside the payload —
    /// through ``NodePropertyCodec/encode(_:)`` — so a key reads exactly what the whole
    /// payload's dictionary held under it.
    struct KeyCapturingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        /// The walk's shared state.
        let capture: Capture

        /// Always empty: the container is the payload's top level.
        var codingPath: [CodingKey] {
            []
        }

        /// Whether `key` is the one being read.
        private func wants(_ key: Key) -> Bool {
            key.stringValue == capture.key
        }

        /// Keeps `value` if `key` is the one being read.
        private func keep(_ value: some Encodable, forKey key: Key) throws {
            guard wants(key) else { return }
            capture.value = try NodePropertyCodec.encode(value)
        }

        /// Records an explicit `null` under the wanted key.
        mutating func encodeNil(forKey key: Key) throws {
            if wants(key) { capture.value = .null }
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: some Encodable, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Bool, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: String, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Double, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Float, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Int, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Int8, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Int16, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Int32, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: Int64, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: UInt, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: UInt8, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: UInt16, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: UInt32, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// Keeps a value written under the wanted key.
        mutating func encode(_ value: UInt64, forKey key: Key) throws {
            try keep(value, forKey: key)
        }

        /// A nested object: not followed.
        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy _: NestedKey.Type,
            forKey _: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            capture.isUnsupported = true
            return KeyedEncodingContainer(KeyCapturingContainer<NestedKey>(capture: Capture(key: "")))
        }

        /// A nested array: not followed.
        mutating func nestedUnkeyedContainer(forKey _: Key) -> UnkeyedEncodingContainer {
            capture.isUnsupported = true
            return RefusingContainer()
        }

        /// A super-encoder: not followed.
        mutating func superEncoder() -> Encoder {
            capture.isUnsupported = true
            return SingleKeyEncoder(capture: Capture(key: ""))
        }

        /// A super-encoder: not followed.
        mutating func superEncoder(forKey _: Key) -> Encoder {
            capture.isUnsupported = true
            return SingleKeyEncoder(capture: Capture(key: ""))
        }
    }
}
