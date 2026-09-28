//
//  NodePropertyCodec+JSON.swift
//  Woodcase
//

import Foundation

/// The JSON layer under ``NodePropertyCodec``.
///
/// A node's shared properties and each kind's payload are already `Codable` in
/// the .pen file's shape, so the codec addresses a single property by encoding
/// the whole payload to a JSON dictionary, replacing one key, and decoding it
/// back. That makes the wire shape of every path correct by construction —
/// there is no second, hand-written description of what a property looks like
/// on disk — and turns a bad value into a real `DecodingError` that the codec
/// reports as ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
extension NodePropertyCodec {
    // MARK: - Swift name → JSON key

    /// The two fields whose JSON key differs from their Swift name.
    ///
    /// Both are uniform across every kind that has them: `fills` is written
    /// `fill` and `effects` is written `effect`. The path vocabulary uses the
    /// Swift names, matching ``PropertyDiff``.
    private static let jsonKeyOverrides: [String: String] = [
        "fills": "fill",
        "effects": "effect",
    ]

    /// The JSON key a property path's field name is stored under.
    static func jsonKey(for field: String) -> String {
        jsonKeyOverrides[field] ?? field
    }

    /// The same two fields, read the other way.
    ///
    /// Derived from ``jsonKeyOverrides`` rather than written out again, so the two
    /// directions cannot disagree about which names differ.
    private static let fieldNameOverrides: [String: String] = Dictionary(
        uniqueKeysWithValues: jsonKeyOverrides.map { ($1, $0) }
    )

    /// The property path's field name a raw .pen key belongs to.
    ///
    /// The inverse of ``jsonKey(for:)``: `fill` is the field `fills`. A key with no
    /// override is its own field name, which is every key but two.
    ///
    /// - Parameter key: A raw .pen key, as a `descendants` map spells it.
    /// - Returns: The field name the shape and coercion tables are keyed by.
    static func fieldName(forRawKey key: String) -> String {
        fieldNameOverrides[key] ?? key
    }

    // MARK: - Encode / decode

    /// Encodes a value to its .pen JSON representation.
    static func encode(_ value: (some Encodable)?) throws -> AnyCodable {
        guard let value else { return .null }
        return try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(value))
    }

    /// Decodes a .pen JSON value into a typed property value.
    static func decode<T: Decodable>(_ type: T.Type, fromValue value: AnyCodable) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }

    /// Encodes a `Codable` payload to the flat JSON dictionary the .pen file holds.
    static func dictionary(from value: some Encodable) throws -> [String: AnyCodable] {
        try JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(value))
    }

    /// Decodes a flat JSON dictionary back into a typed payload.
    static func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: AnyCodable]) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(dictionary))
    }

    // MARK: - Kind payloads

    /// The kind's payload as the flat JSON dictionary the .pen file holds.
    ///
    /// ``PenNode/Kind/ref(_:)`` and ``PenNode/Kind/unknown(typeName:properties:)``
    /// never reach here — the codec addresses their properties directly, because
    /// `RefData` flattens `rootOverrides` into top-level keys and an unknown kind
    /// is already a property dictionary.
    static func kindDictionary(_ kind: PenNode.Kind) throws -> [String: AnyCodable] {
        switch kind {
        case let .frame(data): try dictionary(from: data)
        case let .text(data): try dictionary(from: data)
        case let .rectangle(data): try dictionary(from: data)
        case let .ellipse(data): try dictionary(from: data)
        case let .path(data): try dictionary(from: data)
        case let .group(data): try dictionary(from: data)
        case let .line(data): try dictionary(from: data)
        case let .polygon(data): try dictionary(from: data)
        case let .note(data): try dictionary(from: data)
        case let .prompt(data): try dictionary(from: data)
        case let .context(data): try dictionary(from: data)
        case let .icon(data): try dictionary(from: data)
        case let .script(data): try dictionary(from: data)
        case let .browser(data): try dictionary(from: data)
        case let .connection(data): try dictionary(from: data)
        case let .ref(data): try dictionary(from: data)
        case let .unknown(_, properties): properties
        }
    }

    /// Rebuilds a kind of the same case from a patched JSON dictionary.
    ///
    /// - Parameters:
    ///   - kind: The kind whose case to preserve.
    ///   - dictionary: The patched payload.
    /// - Returns: A kind of the same case carrying the decoded payload.
    /// - Throws: `DecodingError` if the dictionary does not describe this payload.
    static func makeKind(like kind: PenNode.Kind, from dictionary: [String: AnyCodable]) throws -> PenNode.Kind {
        switch kind {
        case .frame: try .frame(decode(PenNode.FrameData.self, from: dictionary))
        case .text: try .text(decode(PenNode.TextData.self, from: dictionary))
        case .rectangle: try .rectangle(decode(PenNode.RectangleData.self, from: dictionary))
        case .ellipse: try .ellipse(decode(PenNode.EllipseData.self, from: dictionary))
        case .path: try .path(decode(PenNode.PathData.self, from: dictionary))
        case .group: try .group(decode(PenNode.GroupData.self, from: dictionary))
        case .line: try .line(decode(PenNode.LineData.self, from: dictionary))
        case .polygon: try .polygon(decode(PenNode.PolygonData.self, from: dictionary))
        case .note: try .note(decode(PenNode.NoteData.self, from: dictionary))
        case .prompt: try .prompt(decode(PenNode.PromptData.self, from: dictionary))
        case .context: try .context(decode(PenNode.ContextData.self, from: dictionary))
        case .icon: try .icon(decode(PenNode.IconData.self, from: dictionary))
        case .script: try .script(decode(PenNode.ScriptData.self, from: dictionary))
        case .browser: try .browser(decode(PenNode.BrowserData.self, from: dictionary))
        case .connection: try .connection(decode(PenNode.ConnectionData.self, from: dictionary))
        case .ref: try .ref(decode(PenNode.RefData.self, from: dictionary))
        case let .unknown(typeName, _): .unknown(typeName: typeName, properties: dictionary)
        }
    }
}
