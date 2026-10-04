//
//  DocumentPropertyCodec.swift
//  Woodcase
//

import Foundation

/// Reads and writes the document root's own properties by key — the vocabulary of
/// ``EditOperation/setDocumentProperties(_:)``.
///
/// The root's counterpart to ``NodePropertyCodec``: values are ``AnyCodable`` in the
/// .pen file's own JSON shape, reading a key and writing the result back is a no-op,
/// and every entry point throws rather than guess. The keys are `fonts`, `version`,
/// `fileToken`, and `extras.<key>` for a root key the model does not claim.
///
/// ```swift
/// try DocumentPropertyCodec.value(at: "version", of: document)        // "2.17"
/// try DocumentPropertyCodec.value(at: "extras.futureKey", of: document) // .null if absent
/// ```
///
/// A root extra holding JSON `null` cannot be told apart from an absent one: null is
/// what clears a key, here as everywhere else in the property vocabulary.
public enum DocumentPropertyCodec {
    /// The key for the root's `fonts` array (``EditableDocument/fonts``).
    public static let fontsKey = "fonts"
    /// The key for the format version (``EditableDocument/version``).
    public static let versionKey = "version"
    /// The key for the editor's per-save token (``EditableDocument/fileToken``).
    public static let fileTokenKey = "fileToken"
    /// The prefix that turns a root key the model does not claim into a property key.
    public static let extrasPrefix = "extras."

    /// The modeled keys, which every document has whether or not it sets them.
    public static let modeledKeys: Set<String> = [fontsKey, versionKey, fileTokenKey]

    /// The document root's own properties, as one value a patch is folded onto.
    struct Root: Equatable {
        var fonts: [PenFontDeclaration]?
        var version: String
        var fileToken: String?
        var extras: PenExtras
    }

    // MARK: - Reading

    /// Reads one document property as it would appear in a .pen file.
    ///
    /// - Parameters:
    ///   - key: A key from the vocabulary above.
    ///   - document: The document to read from.
    /// - Returns: The property's JSON value, or ``AnyCodable/null`` if it is unset.
    /// - Throws: ``EditingError/unknownDocumentProperty(key:)`` for a key outside the
    ///   vocabulary.
    public static func value(at key: String, of document: EditableDocument) throws -> AnyCodable {
        try value(at: key, of: root(of: document))
    }

    /// Reads one key from a root value.
    static func value(at key: String, of root: Root) throws -> AnyCodable {
        switch key {
        case fontsKey: try NodePropertyCodec.encode(root.fonts)
        case versionKey: .string(root.version)
        case fileTokenKey: root.fileToken.map(AnyCodable.string) ?? .null
        default: try root.extras[extraKey(of: key)] ?? .null
        }
    }

    // MARK: - Writing

    /// The document's root as it would stand with every key in `properties` written.
    ///
    /// - Parameters:
    ///   - properties: The keys and values to write.
    ///   - document: The document whose root they patch.
    /// - Returns: The patched root. Nothing is written to `document`.
    /// - Throws: ``EditingError/unknownDocumentProperty(key:)`` or
    ///   ``EditingError/documentPropertyTypeMismatch(key:expected:actual:)`` for the
    ///   first key, in sorted order, that cannot be written.
    static func patched(_ properties: [String: AnyCodable], in document: EditableDocument) throws -> Root {
        var patched = root(of: document)
        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            try set(value, at: key, on: &patched)
        }
        return patched
    }

    /// The root properties a document holds now.
    static func root(of document: EditableDocument) -> Root {
        Root(fonts: document.fonts, version: document.version, fileToken: document.fileToken, extras: document.extras)
    }

    // MARK: - Private

    /// Writes one key onto a root value.
    private static func set(_ value: AnyCodable, at key: String, on root: inout Root) throws {
        switch key {
        case fontsKey:
            if case .null = value {
                root.fonts = nil
                return
            }
            do {
                root.fonts = try NodePropertyCodec.decode([PenFontDeclaration].self, fromValue: value)
            } catch {
                throw mismatch(key, value, expected: "an array of font declarations", failure: error)
            }
        case versionKey:
            guard case let .string(version) = value else {
                throw mismatch(key, value, expected: "a version string")
            }
            root.version = version
        case fileTokenKey:
            switch value {
            case .null: root.fileToken = nil
            case let .string(token): root.fileToken = token
            default: throw mismatch(key, value, expected: "a string, or null to remove it")
            }
        default:
            let extra = try extraKey(of: key)
            var values = root.extras.values
            if case .null = value {
                values.removeValue(forKey: extra)
            } else {
                values[extra] = value
            }
            root.extras = PenExtras(values)
        }
    }

    /// The root key an `extras.<key>` property names, refusing anything else.
    ///
    /// A key the root model claims — `children`, `variables` — is refused: written as an
    /// extra it would collide with the modeled key in the file.
    private static func extraKey(of key: String) throws -> String {
        guard key.hasPrefix(extrasPrefix) else { throw EditingError.unknownDocumentProperty(key: key) }
        let extra = String(key.dropFirst(extrasPrefix.count))
        guard !extra.isEmpty, !PenDocument.claimedKeys.contains(extra) else {
            throw EditingError.unknownDocumentProperty(key: key)
        }
        return extra
    }

    /// The error for a value of the wrong shape.
    private static func mismatch(
        _ key: String,
        _ value: AnyCodable,
        expected: String,
        failure: Error? = nil
    ) -> EditingError {
        .documentPropertyTypeMismatch(
            key: key,
            expected: expected,
            actual: NodePropertyCodec.actualShape(of: value, field: key, failure: failure)
        )
    }
}
