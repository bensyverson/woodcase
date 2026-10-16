//
//  SingleKeyEncoder+RefusingContainer.swift
//  Woodcase
//

import Foundation

extension SingleKeyEncoder {
    /// The container handed out for a route ``SingleKeyEncoder`` does not follow: every
    /// write throws ``Unsupported``, which ends the walk so the caller encodes the
    /// payload whole instead.
    struct RefusingContainer: UnkeyedEncodingContainer, SingleValueEncodingContainer {
        /// Always empty: nothing is written.
        var codingPath: [CodingKey] {
            []
        }

        /// Always zero: nothing is written.
        var count: Int {
            0
        }

        /// Refuses.
        mutating func encodeNil() throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: some Encodable) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Bool) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: String) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Double) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Float) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Int) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Int8) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Int16) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Int32) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: Int64) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: UInt) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: UInt8) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: UInt16) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: UInt32) throws {
            throw Unsupported()
        }

        /// Refuses.
        mutating func encode(_: UInt64) throws {
            throw Unsupported()
        }

        /// A container whose writes are dropped; the walk is already unsupported.
        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy _: NestedKey.Type
        ) -> KeyedEncodingContainer<NestedKey> {
            KeyedEncodingContainer(KeyCapturingContainer<NestedKey>(capture: Capture(key: "")))
        }

        /// Another refusing container.
        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            RefusingContainer()
        }

        /// An encoder whose writes are dropped; the walk is already unsupported.
        mutating func superEncoder() -> Encoder {
            SingleKeyEncoder(capture: Capture(key: ""))
        }
    }
}
