//
//  ImportFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders a document's library imports, as rows and as JSON.
///
/// One row per alias — the alias, how many nodes reach into its namespace, and the path
/// it resolves to:
///
/// ```text
/// imports
///   V      2 refs  ./library.pen
///   icons  0 refs  ../shared/icons.pen
/// ```
///
/// The reference count is the same fact `imports rm` refuses on, so "is this import
/// still needed?" is answered by the listing rather than by trying the removal.
/// ``VariableFormatter`` is the same shape over the variables table; the two are
/// separate because a variable row carries a type and its themed variants and an import
/// row carries neither, and one formatter bending to both would print blank columns.
enum ImportFormatter {
    /// Everything `imports` reports about a document.
    struct Listing: Friendly {
        /// Creates a listing.
        ///
        /// - Parameters:
        ///   - imports: One row per alias, sorted by alias.
        ///   - revision: The document revision this was read at.
        init(imports: [Row], revision: String) {
            self.imports = imports
            self.revision = revision
        }

        /// One row per alias, sorted by alias.
        let imports: [Row]

        /// The document revision this was read at, so a caller that reasons and then
        /// writes can say what it was looking at.
        let revision: String
    }

    /// One import.
    struct Row: Friendly {
        /// Creates a row.
        ///
        /// - Parameters:
        ///   - alias: The namespace prefix the library's identifiers take.
        ///   - path: The file path or URL the alias resolves to.
        ///   - references: How many nodes reach into the namespace.
        init(alias: String, path: String, references: Int) {
            self.alias = alias
            self.path = path
            self.references = references
        }

        /// The namespace prefix the library's identifiers take.
        let alias: String

        /// The file path or URL the alias resolves to.
        let path: String

        /// How many nodes reach into the namespace.
        let references: Int
    }

    // MARK: - Reading a document

    /// Everything `imports` reports about a document.
    ///
    /// - Parameter document: The document to read.
    /// - Returns: Its imports and its revision.
    static func listing(of document: EditableDocument) -> Listing {
        Listing(
            imports: (document.imports ?? [:])
                .sorted { $0.key < $1.key }
                .map { alias, path in row(for: alias, path: path, in: document) },
            revision: document.documentRevision
        )
    }

    /// One alias's row, counted against the document as it now stands.
    ///
    /// - Parameters:
    ///   - alias: The alias to describe.
    ///   - path: The path it resolves to.
    ///   - document: The document holding it.
    /// - Returns: The row.
    static func row(for alias: String, path: String, in document: EditableDocument) -> Row {
        Row(
            alias: alias,
            path: path,
            references: NameInUse.importAlias(alias, in: document).count
        )
    }

    // MARK: - Rendering

    /// The whole listing as rows.
    ///
    /// - Parameters:
    ///   - listing: What to render.
    ///   - fileName: The file's name, for the sentence a document with no imports gets —
    ///     an empty listing is a true answer, not an error.
    /// - Returns: The text, with no trailing newline.
    static func text(_ listing: Listing, in fileName: String) -> String {
        guard !listing.imports.isEmpty else { return "No imports in \(fileName)." }
        return (["imports"] + lines(for: listing.imports)).joined(separator: "\n")
    }

    /// Import rows, aligned so the paths line up.
    ///
    /// - Parameter rows: The imports to render.
    /// - Returns: One line per row, indented two spaces.
    static func lines(for rows: [Row]) -> [String] {
        let aliasWidth = rows.map(\.alias.count).max() ?? 0
        let countWidth = rows.map { text(for: $0.references).count }.max() ?? 0
        return rows.map { row in
            "  " + padded(row.alias, to: aliasWidth)
                + "  " + padded(text(for: row.references), to: countWidth)
                + "  " + row.path
        }
    }

    /// Anything `imports` answers with, as JSON.
    ///
    /// - Parameter value: The report to encode.
    /// - Returns: Pretty-printed JSON with sorted keys, so a golden test can pin it.
    /// - Throws: Whatever `JSONEncoder` throws.
    static func json(_ value: some Encodable) throws -> String {
        try VariableFormatter.json(value)
    }

    /// A reference count as it appears in a row.
    ///
    /// - Parameter references: How many nodes reach into the namespace.
    /// - Returns: `"2 refs"`, `"1 ref"`.
    static func text(for references: Int) -> String {
        "\(references) " + (references == 1 ? "ref" : "refs")
    }

    // MARK: - Private

    private static func padded(_ text: String, to width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }
}
