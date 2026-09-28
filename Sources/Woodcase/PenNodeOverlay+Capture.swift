//
//  PenNodeOverlay+Capture.swift
//  Woodcase
//

import Foundation

extension PenNodeOverlay {
    /// An encoder that records a node's top-level values instead of encoding them.
    ///
    /// A node's `encode(to:)` writes one flat object through keyed containers; each value
    /// handed to one is kept here as the typed value it is — a `PenFills`, a `[PenNode]` —
    /// and nothing beneath it is visited. A write through a container the overlay cannot
    /// read back (a nested one, an unkeyed or single-value one at the top) marks the
    /// capture ``Storage/declined``, and ``PenNodeOverlay/merged(_:with:)`` then declines.
    final class Capture: Encoder {
        /// One captured value: what the node wrote, or an explicit `null`.
        enum Value {
            /// A value, as the type the node encoded it as.
            case value(Any)

            /// An explicit `encodeNil`.
            case null
        }

        /// The values captured so far, shared by every container the encoder hands out —
        /// a node writes its extras, shared properties and payload through three.
        final class Storage {
            /// Key → value; a later write of a key replaces an earlier one, as in JSON.
            var values: [String: Value] = [:]

            /// Whether the node wrote something the overlay cannot read back.
            var declined = false
        }

        /// Where the values land.
        let storage = Storage()

        var codingPath: [CodingKey] {
            []
        }

        var userInfo: [CodingUserInfoKey: Any] {
            [:]
        }

        func container<Key: CodingKey>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> {
            KeyedEncodingContainer(Keyed<Key>(storage: storage))
        }

        func unkeyedContainer() -> UnkeyedEncodingContainer {
            storage.declined = true
            return Sink()
        }

        func singleValueContainer() -> SingleValueEncodingContainer {
            storage.declined = true
            return Sink()
        }
    }
}

// MARK: - Containers

extension PenNodeOverlay.Capture {
    /// The node object's container: every value is recorded, not encoded.
    struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        /// Where the values land.
        let storage: Storage

        var codingPath: [CodingKey] {
            []
        }

        /// Records one value.
        private func keep(_ value: Any, _ key: Key) {
            storage.values[key.stringValue] = .value(value)
        }

        mutating func encodeNil(forKey key: Key) throws {
            storage.values[key.stringValue] = .null
        }

        mutating func encode(_ value: some Encodable, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Bool, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: String, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Double, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Float, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Int, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Int8, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Int16, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Int32, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: Int64, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: UInt, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: UInt8, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: UInt16, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: UInt32, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func encode(_ value: UInt64, forKey key: Key) throws {
            keep(value, key)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy _: NestedKey.Type,
            forKey _: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            storage.declined = true
            return KeyedEncodingContainer(Keyed<NestedKey>(storage: Storage()))
        }

        mutating func nestedUnkeyedContainer(forKey _: Key) -> UnkeyedEncodingContainer {
            storage.declined = true
            return Sink()
        }

        mutating func superEncoder() -> Encoder {
            storage.declined = true
            return PenNodeOverlay.Capture()
        }

        mutating func superEncoder(forKey _: Key) -> Encoder {
            storage.declined = true
            return PenNodeOverlay.Capture()
        }
    }

    /// Somewhere to write what the overlay has already declined to read back.
    struct Sink: UnkeyedEncodingContainer, SingleValueEncodingContainer {
        var codingPath: [CodingKey] {
            []
        }

        var count: Int {
            0
        }

        mutating func encodeNil() throws {}
        mutating func encode(_: some Encodable) throws {}
        mutating func encode(_: Bool) throws {}
        mutating func encode(_: String) throws {}
        mutating func encode(_: Double) throws {}
        mutating func encode(_: Float) throws {}
        mutating func encode(_: Int) throws {}
        mutating func encode(_: Int8) throws {}
        mutating func encode(_: Int16) throws {}
        mutating func encode(_: Int32) throws {}
        mutating func encode(_: Int64) throws {}
        mutating func encode(_: UInt) throws {}
        mutating func encode(_: UInt8) throws {}
        mutating func encode(_: UInt16) throws {}
        mutating func encode(_: UInt32) throws {}
        mutating func encode(_: UInt64) throws {}

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy _: NestedKey.Type
        ) -> KeyedEncodingContainer<NestedKey> {
            KeyedEncodingContainer(Keyed<NestedKey>(storage: Storage()))
        }

        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            Sink()
        }

        mutating func superEncoder() -> Encoder {
            PenNodeOverlay.Capture()
        }
    }
}
