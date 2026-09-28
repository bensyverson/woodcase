//
//  AnyCodableDecoder.swift
//  Woodcase
//

import Foundation

/// A decoder that reads a typed value straight out of an ``AnyCodable`` tree.
///
/// An override is stored as ``AnyCodable`` — the JSON it was written as, parsed — and
/// applying one used to turn it back into text with `JSONEncoder` so `JSONDecoder` could
/// read it into the node's typed properties. This reads the tree in memory instead, and
/// answers exactly what that round trip answered: the same values accepted, the same
/// refused, the same numbers produced. `AnyCodableDecoderTests` holds it to
/// `JSONDecoder` case by case.
///
/// The one rule the round trip hid is how numbers cross. `JSONEncoder` writes the double
/// `3.0` as `3`, and `JSONDecoder` reads `3` as an integer when one is asked for — so an
/// integral double decodes as an `Int`, and a double that is not integral, or does not
/// fit, is refused. ``AnyCodable`` itself tries `Int` before `Double`, so a value read
/// back as ``AnyCodable`` comes out normalized the same way (``normalized(_:)``).
///
/// It decodes in ``PenDecodingMode/file`` mode, as the plain `JSONDecoder` it replaces did.
struct AnyCodableDecoder: Decoder {
    /// The value being decoded.
    let value: AnyCodable

    /// The keys from the root of the decode to ``value``.
    let codingPath: [CodingKey]

    /// Empty: a decode with no mode set reads in ``PenDecodingMode/file`` mode.
    var userInfo: [CodingUserInfoKey: Any] {
        [:]
    }

    /// Wraps a value.
    ///
    /// - Parameters:
    ///   - value: The tree to decode.
    ///   - codingPath: Where the value sits, for error messages.
    init(_ value: AnyCodable, codingPath: [CodingKey] = []) {
        self.value = value
        self.codingPath = codingPath
    }

    /// Decodes a typed value from an ``AnyCodable`` tree.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - value: The tree.
    ///   - codingPath: Where the value sits, for error messages.
    /// - Returns: The decoded value.
    /// - Throws: `DecodingError` wherever `JSONDecoder` would have thrown one.
    static func decode<T: Decodable>(_ type: T.Type, from value: AnyCodable, codingPath: [CodingKey] = []) throws -> T {
        if type == AnyCodable.self, let normalized = normalized(value) as? T {
            return normalized
        }
        return try T(from: AnyCodableDecoder(value, codingPath: codingPath))
    }

    /// The value as a round trip through JSON text would give it back as ``AnyCodable``.
    ///
    /// An integral double that fits an `Int` becomes one — `3.0` is written `3`, and
    /// ``AnyCodable`` tries `Int` first — and everything else is unchanged.
    ///
    /// - Parameter value: The value to normalize.
    /// - Returns: The normalized value.
    static func normalized(_ value: AnyCodable) -> AnyCodable {
        switch value {
        case let .double(number): Int(exactly: number).map(AnyCodable.int) ?? value
        case let .array(elements): .array(elements.map(normalized))
        case let .dictionary(entries): .dictionary(entries.mapValues(normalized))
        case .null, .bool, .int, .string: value
        }
    }

    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case let .dictionary(entries) = value else {
            throw Self.mismatch([String: AnyCodable].self, value, codingPath)
        }
        return KeyedDecodingContainer(Keyed<Key>(entries: entries, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case let .array(elements) = value else {
            throw Self.mismatch([AnyCodable].self, value, codingPath)
        }
        return Unkeyed(elements: elements, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleValue(value: value, codingPath: codingPath)
    }

    // MARK: - Scalars

    /// Reads a `Bool`; only a JSON boolean is one.
    static func bool(_ value: AnyCodable, _ path: [CodingKey]) throws -> Bool {
        guard case let .bool(flag) = value else { throw mismatch(Bool.self, value, path) }
        return flag
    }

    /// Reads a `String`; only a JSON string is one.
    static func string(_ value: AnyCodable, _ path: [CodingKey]) throws -> String {
        guard case let .string(text) = value else { throw mismatch(String.self, value, path) }
        return text
    }

    /// Reads a `Double` from any JSON number.
    static func double(_ value: AnyCodable, _ path: [CodingKey]) throws -> Double {
        switch value {
        case let .int(number): Double(number)
        case let .double(number): number
        default: throw mismatch(Double.self, value, path)
        }
    }

    /// Reads a `Float` from any JSON number that fits one.
    static func float(_ value: AnyCodable, _ path: [CodingKey]) throws -> Float {
        let number = try double(value, path)
        let narrowed = Float(number)
        guard narrowed.isFinite || !number.isFinite else { throw mismatch(Float.self, value, path) }
        return narrowed
    }

    /// Reads an integer from a JSON number that is integral and in range.
    static func integer<T: FixedWidthInteger>(_ value: AnyCodable, _ path: [CodingKey]) throws -> T {
        let result: T? = switch value {
        case let .int(number): T(exactly: number)
        case let .double(number): T(exactly: number)
        default: nil
        }
        guard let result else { throw mismatch(T.self, value, path) }
        return result
    }

    /// The error for a value of the wrong shape.
    ///
    /// Names only the JSON kind found — the type asked for rides in the error itself: a
    /// decode that tries alternatives with `try?` builds one of these per refusal, and
    /// printing the value or the type was most of what a refusal cost. No reader sees the
    /// wording: ``PenNodePatcher`` reports a refused patch in `JSONDecoder`'s words.
    static func mismatch(_ type: Any.Type, _ value: AnyCodable, _ path: [CodingKey]) -> DecodingError {
        let context = DecodingError.Context(
            codingPath: path,
            debugDescription: "Found " + kind(of: value) + " instead."
        )
        if case .null = value { return .valueNotFound(type, context) }
        return .typeMismatch(type, context)
    }

    /// The JSON kind of a value, as `JSONDecoder`'s errors name it.
    private static func kind(of value: AnyCodable) -> String {
        switch value {
        case .null: "null"
        case .bool: "bool"
        case .int, .double: "number"
        case .string: "a string"
        case .array: "an array"
        case .dictionary: "a dictionary"
        }
    }
}
