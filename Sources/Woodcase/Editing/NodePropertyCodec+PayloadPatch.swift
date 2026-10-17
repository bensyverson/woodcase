//
//  NodePropertyCodec+PayloadPatch.swift
//  Woodcase
//

import Foundation

/// Writing one key of a node's `common` or `kind` payload without sending the rest of it
/// through JSON.
///
/// A write used to encode the whole payload to a JSON dictionary, set one key and decode
/// the dictionary back — so writing a board's `kind.width` encoded and decoded every node
/// under it. Now the payload's own `encode(to:)` runs into ``PenNodeOverlay/Capture``,
/// which keeps each key's value as the typed value it is, and the payload's own
/// `init(from:)` reads ``PenNodeOverlay``, which answers the written key from the new
/// value and every other key with the captured value itself — `children` is the same
/// array, never a decoded copy. The new value's wire shape, and the error a bad one
/// raises, still come from the payload's `Codable` conformance. Where the overlay declines
/// — a payload that encodes through a nested container, or reads a key back as another
/// type than it wrote — the write takes the whole round trip instead, so it is never
/// wrong, only occasionally not faster.
extension NodePropertyCodec {
    /// Returns `payload` with one field set to `value`.
    ///
    /// Equal to decoding `patching(dictionary(from: payload), field:value:)`, without
    /// encoding or decoding the payload's other keys wherever ``overlaying(_:key:value:)``
    /// can answer.
    ///
    /// - Parameters:
    ///   - payload: The `common` or `kind` payload to patch.
    ///   - field: The property path's field name; ``jsonKey(for:)`` spells its key.
    ///   - value: The new JSON value; ``AnyCodable/null`` removes the key.
    /// - Returns: The patched payload.
    /// - Throws: The `DecodingError` the payload raises for the new value.
    static func patchingPayload<Payload: Codable>(
        _ payload: Payload,
        field: String,
        value: AnyCodable
    ) throws -> Payload {
        if let patched = try overlaying(payload, key: jsonKey(for: field), value: value) {
            return patched
        }
        return try decode(Payload.self, from: patching(dictionary(from: payload), field: field, value: value))
    }

    /// Returns `payload` with one top-level key set to `value`, through
    /// ``PenNodeOverlay`` — or `nil` where the overlay declines.
    ///
    /// - Parameters:
    ///   - payload: The payload to patch.
    ///   - key: The JSON key, as the payload's `CodingKeys` spell it.
    ///   - value: The new JSON value; ``AnyCodable/null`` removes the key, so the payload
    ///     decodes as though the file never wrote it.
    /// - Returns: The patched payload, or `nil` when the payload encodes or decodes itself
    ///   in a way the overlay does not follow.
    /// - Throws: The `DecodingError` the payload raises for the new value.
    static func overlaying<Payload: Codable>(
        _ payload: Payload,
        key: String,
        value: AnyCodable
    ) throws -> Payload? {
        let capture = PenNodeOverlay.Capture()
        try payload.encode(to: capture)
        guard !capture.storage.declined else { return nil }
        var captured = capture.storage.values
        captured.removeValue(forKey: key)
        var patch: [String: AnyCodable] = [:]
        if value != .null {
            patch[key] = value
        }
        do {
            return try Payload(from: PenNodeOverlay(captured: captured, patch: patch))
        } catch is PenNodeOverlay.Unsupported {
            return nil
        }
    }

    /// Returns `kind` with one field of its payload set to `value`.
    ///
    /// - Parameters:
    ///   - kind: The kind to patch.
    ///   - field: The property path's field name.
    ///   - value: The new JSON value; ``AnyCodable/null`` removes the key.
    /// - Returns: A kind of the same case carrying the patched payload.
    /// - Throws: The `DecodingError` the payload raises for the new value.
    static func patchingKind(_ kind: PenNode.Kind, field: String, value: AnyCodable) throws -> PenNode.Kind {
        switch kind {
        case let .frame(data): try .frame(patchingPayload(data, field: field, value: value))
        case let .text(data): try .text(patchingPayload(data, field: field, value: value))
        case let .rectangle(data): try .rectangle(patchingPayload(data, field: field, value: value))
        case let .ellipse(data): try .ellipse(patchingPayload(data, field: field, value: value))
        case let .path(data): try .path(patchingPayload(data, field: field, value: value))
        case let .group(data): try .group(patchingPayload(data, field: field, value: value))
        case let .line(data): try .line(patchingPayload(data, field: field, value: value))
        case let .polygon(data): try .polygon(patchingPayload(data, field: field, value: value))
        case let .note(data): try .note(patchingPayload(data, field: field, value: value))
        case let .prompt(data): try .prompt(patchingPayload(data, field: field, value: value))
        case let .context(data): try .context(patchingPayload(data, field: field, value: value))
        case let .icon(data): try .icon(patchingPayload(data, field: field, value: value))
        case let .script(data): try .script(patchingPayload(data, field: field, value: value))
        case let .browser(data): try .browser(patchingPayload(data, field: field, value: value))
        case let .connection(data): try .connection(patchingPayload(data, field: field, value: value))
        case let .ref(data): try .ref(patchingPayload(data, field: field, value: value))
        case let .unknown(typeName, properties):
            .unknown(typeName: typeName, properties: patching(properties, field: field, value: value))
        }
    }
}
