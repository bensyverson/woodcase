//
//  PenMetadata.swift
//  Woodcase
//

import Foundation

/// Metadata attached to a .pen node.
///
/// The `.pen` schema declares `metadata.type` as a field, but Pen itself does not
/// always write one — a node's metadata object can be present with only extension
/// keys. `PenMetadata` mirrors that: ``type`` is optional, decodes to `nil` when the
/// key is absent, and is written back out only when it holds a value, so reading and
/// re-writing a file that never had `type` round-trips exactly, adding no key Pen
/// never wrote. A caller that must satisfy the schema when *creating* a metadata
/// object from nothing (`woodcase set common.metadata._role=…`) chooses its own
/// default explicitly, rather than relying on one here — see
/// `NodePropertyCodec.folding(_:onto:)`.
///
/// ## Codable Format
///
/// Encodes as a flat JSON dictionary:
/// ```json
/// {"type": "component", "_role": "button", "_action": "submit"}
/// ```
/// This matches the existing `.pen` wire format — there is no nesting
/// or wrapper key. The `type` key is extracted during decoding; all other
/// keys go into ``extensions``. When `type` is absent, decoding leaves it `nil`
/// and encoding omits the key.
///
/// ## Subscript Access
///
/// A convenience subscript allows accessing any metadata key:
/// ```swift
/// metadata["_role"]   // Returns AnyCodable? from extensions
/// metadata["type"]    // Returns .string(type), or nil if type is absent
/// ```
public struct PenMetadata: Friendly {
    /// Describes the node's metadata type (e.g. `"component"`, `"screen"`), or
    /// `nil` when the `.pen` file's metadata object never declared one.
    public var type: String?

    /// Additional key-value pairs beyond `type`.
    public var extensions: [String: AnyCodable]

    /// Creates a metadata value with an optional type and optional extensions.
    ///
    /// - Parameters:
    ///   - type: The metadata type string, or `nil` to leave it undeclared.
    ///     Defaults to `nil`.
    ///   - extensions: Additional key-value pairs. Defaults to empty.
    public init(type: String? = nil, extensions: [String: AnyCodable] = [:]) {
        self.type = type
        self.extensions = extensions
    }

    /// Convenience subscript for accessing type or extension keys.
    ///
    /// - Parameter key: The metadata key to look up or set.
    /// - Returns: The value for the key, or `nil` if not present.
    ///   For `"type"`, returns `.string(type)` when ``type`` holds a value, or
    ///   `nil` when it does not.
    public subscript(key: String) -> AnyCodable? {
        get {
            if key == "type" {
                return type.map(AnyCodable.string)
            }
            return extensions[key]
        }
        set {
            if key == "type" {
                if case let .string(s) = newValue {
                    type = s
                } else if newValue == nil {
                    type = nil
                }
            } else {
                extensions[key] = newValue
            }
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Extract type when present; absent stays nil rather than a fabricated default,
        // so a file Pen wrote without one round-trips without gaining the key.
        let typeKey = DynamicCodingKey(stringValue: "type")
        if container.contains(typeKey) {
            type = try container.decode(String.self, forKey: typeKey)
        } else {
            type = nil
        }

        // All other keys go into extensions
        var ext: [String: AnyCodable] = [:]
        for key in container.allKeys where key.stringValue != "type" {
            ext[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
        }
        extensions = ext
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        // Write type only when present, so a file that never had one gets no key added.
        if let type {
            try container.encode(type, forKey: DynamicCodingKey(stringValue: "type"))
        }

        // Write all extensions as top-level keys
        for (key, value) in extensions {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension PenMetadata: ExpressibleByDictionaryLiteral {
    /// Creates a `PenMetadata` from a dictionary literal.
    ///
    /// If a `"type"` key is present, it becomes the ``type`` property.
    /// All other keys go into ``extensions``. If `"type"` is absent,
    /// ``type`` is left `nil`.
    ///
    /// ```swift
    /// let metadata: PenMetadata = ["type": "component", "_role": .string("button")]
    /// ```
    public init(dictionaryLiteral elements: (String, AnyCodable)...) {
        var typeValue: String?
        var ext: [String: AnyCodable] = [:]
        for (key, value) in elements {
            if key == "type", case let .string(s) = value {
                typeValue = s
            } else {
                ext[key] = value
            }
        }
        type = typeValue
        extensions = ext
    }
}
