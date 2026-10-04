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
/// `fileToken`, `extras.<key>` for a root key the model does not claim, and
/// `variables`, `imports` and `themes` for whether each table is declared at all.
///
/// A table key carries only its declaration: `{}` when the file writes the table —
/// however many entries it holds — and ``AnyCodable/null`` when it leaves the table
/// out. The entries have operations of their own; the key exists because a file may
/// write an empty table (`"variables": {}`) and that is a difference a merge must be
/// able to reproduce. Writing `{}` declares a table and leaves its entries alone;
/// writing null leaves out a table that holds no entries, and is refused for one that
/// does, since its inverse could not put them back.
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

    /// The modeled keys, which every document has whether or not it sets them —
    /// including one per table (`variables`, `imports`, `themes`).
    public static let modeledKeys: Set<String> = Set([fontsKey, versionKey, fileTokenKey] + DocumentChangeKey.Table.allCases.map(\.rawValue))

    /// The document root's own properties, as one value a patch is folded onto.
    struct Root: Equatable {
        var fonts: [PenFontDeclaration]?
        var version: String
        var fileToken: String?
        var extras: PenExtras
        /// The tables the file writes, empty or not.
        var declaredTables: Set<DocumentChangeKey.Table>
        /// The tables that hold at least one entry; never changed by a patch.
        var populatedTables: Set<DocumentChangeKey.Table>
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
        default:
            if let table = DocumentChangeKey.Table(rawValue: key) {
                root.declaredTables.contains(table) ? .dictionary([:]) : .null
            } else {
                try root.extras[extraKey(of: key)] ?? .null
            }
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
        var declared: Set<DocumentChangeKey.Table> = []
        var populated: Set<DocumentChangeKey.Table> = []
        for (table, count) in [
            (DocumentChangeKey.Table.variables, document.variables?.count),
            (.imports, document.imports?.count),
            (.themes, document.themes?.count),
        ] {
            guard let count else { continue }
            declared.insert(table)
            if count > 0 { populated.insert(table) }
        }
        return Root(
            fonts: document.fonts, version: document.version, fileToken: document.fileToken, extras: document.extras,
            declaredTables: declared, populatedTables: populated
        )
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
            if let table = DocumentChangeKey.Table(rawValue: key) {
                try declare(table, value, on: &root)
                return
            }
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

    /// Writes a table's declaration: `{}` declares it, null leaves out an empty one.
    private static func declare(_ table: DocumentChangeKey.Table, _ value: AnyCodable, on root: inout Root) throws {
        switch value {
        case let .dictionary(entries) where entries.isEmpty:
            root.declaredTables.insert(table)
        case .null where !root.populatedTables.contains(table):
            root.declaredTables.remove(table)
        case .null:
            throw mismatch(table.rawValue, value, expected: "{} — null leaves out only a table with no entries; remove them first")
        default:
            throw mismatch(table.rawValue, value, expected: "{} to declare the table, or null to leave it out")
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
