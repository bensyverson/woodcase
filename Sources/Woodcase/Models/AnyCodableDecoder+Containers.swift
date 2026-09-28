//
//  AnyCodableDecoder+Containers.swift
//  Woodcase
//

import Foundation

/// The three containers ``AnyCodableDecoder`` hands out, each answering as
/// `JSONDecoder`'s do: a missing key is `keyNotFound`, a `null` is `valueNotFound` to
/// anything but `decodeNil`, and a super-decoder for a missing key reads `null`.
extension AnyCodableDecoder {
    /// A JSON object's container.
    struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
        /// The object's entries.
        let entries: [String: AnyCodable]

        /// The keys from the root of the decode to this object.
        let codingPath: [CodingKey]

        var allKeys: [Key] {
            entries.keys.compactMap { Key(stringValue: $0) }
        }

        func contains(_ key: Key) -> Bool {
            entries[key.stringValue] != nil
        }

        /// The entry under `key`, or `keyNotFound`.
        private func entry(_ key: Key) throws -> AnyCodable {
            guard let value = entries[key.stringValue] else {
                throw DecodingError.keyNotFound(key, DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "No value associated with key \(key.stringValue)."
                ))
            }
            return value
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            try entry(key) == .null
        }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            try AnyCodableDecoder.decode(type, from: entry(key), codingPath: codingPath + [key])
        }

        func decode(_: Bool.Type, forKey key: Key) throws -> Bool {
            try AnyCodableDecoder.bool(entry(key), codingPath + [key])
        }

        func decode(_: String.Type, forKey key: Key) throws -> String {
            try AnyCodableDecoder.string(entry(key), codingPath + [key])
        }

        func decode(_: Double.Type, forKey key: Key) throws -> Double {
            try AnyCodableDecoder.double(entry(key), codingPath + [key])
        }

        func decode(_: Float.Type, forKey key: Key) throws -> Float {
            try AnyCodableDecoder.float(entry(key), codingPath + [key])
        }

        func decode(_: Int.Type, forKey key: Key) throws -> Int {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: Int8.Type, forKey key: Key) throws -> Int8 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: Int16.Type, forKey key: Key) throws -> Int16 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: Int32.Type, forKey key: Key) throws -> Int32 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: Int64.Type, forKey key: Key) throws -> Int64 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: UInt.Type, forKey key: Key) throws -> UInt {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: UInt8.Type, forKey key: Key) throws -> UInt8 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: UInt16.Type, forKey key: Key) throws -> UInt16 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: UInt32.Type, forKey key: Key) throws -> UInt32 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func decode(_: UInt64.Type, forKey key: Key) throws -> UInt64 {
            try AnyCodableDecoder.integer(entry(key), codingPath + [key])
        }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type,
            forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try AnyCodableDecoder(entry(key), codingPath: codingPath + [key]).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            try AnyCodableDecoder(entry(key), codingPath: codingPath + [key]).unkeyedContainer()
        }

        func superDecoder() throws -> Decoder {
            AnyCodableDecoder(entries["super"] ?? .null, codingPath: codingPath + [DynamicCodingKey(stringValue: "super")])
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            AnyCodableDecoder(entries[key.stringValue] ?? .null, codingPath: codingPath + [key])
        }
    }

    /// A JSON array's container.
    struct Unkeyed: UnkeyedDecodingContainer {
        /// The array's elements.
        let elements: [AnyCodable]

        /// The keys from the root of the decode to this array.
        let codingPath: [CodingKey]

        /// The index of the next element to decode.
        private(set) var currentIndex = 0

        /// Wraps an array.
        init(elements: [AnyCodable], codingPath: [CodingKey]) {
            self.elements = elements
            self.codingPath = codingPath
        }

        var count: Int? {
            elements.count
        }

        var isAtEnd: Bool {
            currentIndex >= elements.count
        }

        /// The path to the next element.
        private var elementPath: [CodingKey] {
            codingPath + [IndexKey(currentIndex)]
        }

        /// The next element, not yet consumed, or `valueNotFound` at the end.
        private func peek(_ type: Any.Type) throws -> AnyCodable {
            guard !isAtEnd else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(
                    codingPath: elementPath,
                    debugDescription: "Unkeyed container is at end."
                ))
            }
            return elements[currentIndex]
        }

        /// Decodes the next element with `read` and consumes it once it has decoded.
        private mutating func next<T>(_ read: (AnyCodable, [CodingKey]) throws -> T) throws -> T {
            let result = try read(peek(T.self), elementPath)
            currentIndex += 1
            return result
        }

        mutating func decodeNil() throws -> Bool {
            guard try peek(Never.self) == .null else { return false }
            currentIndex += 1
            return true
        }

        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try next { try AnyCodableDecoder.decode(type, from: $0, codingPath: $1) }
        }

        mutating func decode(_: Bool.Type) throws -> Bool {
            try next(AnyCodableDecoder.bool)
        }

        mutating func decode(_: String.Type) throws -> String {
            try next(AnyCodableDecoder.string)
        }

        mutating func decode(_: Double.Type) throws -> Double {
            try next(AnyCodableDecoder.double)
        }

        mutating func decode(_: Float.Type) throws -> Float {
            try next(AnyCodableDecoder.float)
        }

        mutating func decode(_: Int.Type) throws -> Int {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: Int8.Type) throws -> Int8 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: Int16.Type) throws -> Int16 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: Int32.Type) throws -> Int32 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: Int64.Type) throws -> Int64 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: UInt.Type) throws -> UInt {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: UInt8.Type) throws -> UInt8 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: UInt16.Type) throws -> UInt16 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: UInt32.Type) throws -> UInt32 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func decode(_: UInt64.Type) throws -> UInt64 {
            try next(AnyCodableDecoder.integer)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try next { try AnyCodableDecoder($0, codingPath: $1).container(keyedBy: type) }
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            try next { try AnyCodableDecoder($0, codingPath: $1).unkeyedContainer() }
        }

        mutating func superDecoder() throws -> Decoder {
            try next { AnyCodableDecoder($0, codingPath: $1) }
        }
    }

    /// A single value's container.
    struct SingleValue: SingleValueDecodingContainer {
        /// The value.
        let value: AnyCodable

        /// The keys from the root of the decode to the value.
        let codingPath: [CodingKey]

        func decodeNil() -> Bool {
            value == .null
        }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try AnyCodableDecoder.decode(type, from: value, codingPath: codingPath)
        }

        func decode(_: Bool.Type) throws -> Bool {
            try AnyCodableDecoder.bool(value, codingPath)
        }

        func decode(_: String.Type) throws -> String {
            try AnyCodableDecoder.string(value, codingPath)
        }

        func decode(_: Double.Type) throws -> Double {
            try AnyCodableDecoder.double(value, codingPath)
        }

        func decode(_: Float.Type) throws -> Float {
            try AnyCodableDecoder.float(value, codingPath)
        }

        func decode(_: Int.Type) throws -> Int {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: Int8.Type) throws -> Int8 {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: Int16.Type) throws -> Int16 {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: Int32.Type) throws -> Int32 {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: Int64.Type) throws -> Int64 {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: UInt.Type) throws -> UInt {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: UInt8.Type) throws -> UInt8 {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: UInt16.Type) throws -> UInt16 {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: UInt32.Type) throws -> UInt32 {
            try AnyCodableDecoder.integer(value, codingPath)
        }

        func decode(_: UInt64.Type) throws -> UInt64 {
            try AnyCodableDecoder.integer(value, codingPath)
        }
    }

    /// An array index as a coding key, for error paths.
    struct IndexKey: CodingKey {
        let intValue: Int?

        var stringValue: String {
            "Index \(intValue ?? 0)"
        }

        /// Names an index.
        init(_ index: Int) {
            intValue = index
        }

        init?(stringValue _: String) {
            nil
        }

        init?(intValue: Int) {
            self.intValue = intValue
        }
    }
}
