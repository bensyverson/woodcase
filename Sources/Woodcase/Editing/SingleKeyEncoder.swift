//
//  SingleKeyEncoder.swift
//  Woodcase
//

import Foundation

/// An `Encoder` that runs a payload's own `encode(to:)` but keeps one top-level key,
/// encoding that key's value alone and skipping every other.
///
/// Reading `kind.width` of a frame used to encode the frame's whole payload — every
/// sibling property and every descendant in `children` — then pick one key out of the
/// dictionary. This walks the same `encode(to:)`, so the key's wire shape still comes
/// from the type's own `Codable` conformance and cannot drift from the file, but the
/// siblings are dropped before anything encodes them.
///
/// It understands what the node payloads do: one or more keyed containers at the top
/// level. Anything else — a top-level unkeyed or single-value container, a nested
/// container or a super-encoder under the wanted key — sets
/// ``Capture/isUnsupported`` instead, and ``value(forKey:in:)`` answers `nil` so the
/// caller falls back to encoding the whole payload.
///
/// ```swift
/// let width = try SingleKeyEncoder.value(forKey: "width", in: frameData) // .some(.int(320))
/// ```
struct SingleKeyEncoder: Encoder {
    /// What the walk found, shared by the encoder and its containers.
    final class Capture {
        /// The top-level key to keep.
        let key: String
        /// The key's encoded value, once the payload wrote it.
        var value: AnyCodable?
        /// Whether the payload encoded itself in a way this encoder does not follow.
        var isUnsupported = false

        /// Creates a capture for one key.
        init(key: String) {
            self.key = key
        }
    }

    /// The thrown signal that the payload took a route this encoder does not follow.
    struct Unsupported: Error {}

    /// The walk's shared state.
    let capture: Capture

    /// Always empty: the encoder is only ever at the payload's top level.
    var codingPath: [CodingKey] {
        []
    }

    /// Always empty, as `JSONEncoder`'s is by default.
    var userInfo: [CodingUserInfoKey: Any] {
        [:]
    }

    /// Encodes one top-level key of a payload.
    ///
    /// - Parameters:
    ///   - key: The JSON key to read, as the payload's `CodingKeys` spell it.
    ///   - payload: The value whose key to encode.
    /// - Returns: `.some(value)` with the key's JSON value — ``AnyCodable/null`` when the
    ///   payload does not write the key — or `nil` when the payload encodes itself in a
    ///   way this encoder does not follow and the caller must encode it whole.
    /// - Throws: Whatever encoding the key's own value throws.
    static func value(forKey key: String, in payload: some Encodable) throws -> AnyCodable? {
        let capture = Capture(key: key)
        do {
            try payload.encode(to: SingleKeyEncoder(capture: capture))
        } catch is Unsupported {
            return nil
        }
        guard !capture.isUnsupported else { return nil }
        return capture.value ?? .null
    }

    /// A keyed container over the payload's top level that keeps the wanted key.
    func container<Key: CodingKey>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(KeyCapturingContainer<Key>(capture: capture))
    }

    /// A payload that is not an object: not followed.
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        capture.isUnsupported = true
        return RefusingContainer()
    }

    /// A payload that is not an object: not followed.
    func singleValueContainer() -> SingleValueEncodingContainer {
        capture.isUnsupported = true
        return RefusingContainer()
    }
}
