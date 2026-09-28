//
//  PenSchema.swift
//  Woodcase
//

import Foundation

/// The .pen property vocabulary, assembled from the decoders — what `woodcase schema`
/// prints.
///
/// Nothing here is a second description of the format. The paths are the ones
/// `PropertyDiff.allKindKeys` gives the codec, so a table lists exactly what `set`
/// accepts and a refusal lists; the wire keys come from ``NodePropertyCodec``'s own name
/// mapping; the forms, spellings and nested key tables come from
/// ``NodePropertyCodec/shape(of:)``. Adding a property to a decoder adds a row here, and
/// `PenSchemaTests` fails if it does not.
///
/// ```swift
/// PenSchema.table(for: .text).properties.first { $0.path == "kind.textGrowth" }?.value
/// // "auto" | "fixed-width" | "fixed-width-height"
/// ```
public enum PenSchema {
    /// The properties every node of every type takes.
    public static var common: PenSchemaTable {
        PenSchemaTable(
            type: nil,
            summary: "every node of every type takes these",
            properties: rows(for: NodePropertyCodec.commonPaths, prefix: NodePropertyCodec.commonPrefix)
        )
    }

    /// The kind-specific properties one node type takes.
    ///
    /// - Parameter type: The node type to describe.
    /// - Returns: Its `kind.*` rows, sorted by path. The `common.*` rows are not
    ///   repeated: they are the same thirteen on all sixteen types, and burying the
    ///   eight to twenty-three rows that differ under them is what the reader came for.
    public static func table(for type: PenNode.NodeType) -> PenSchemaTable {
        PenSchemaTable(
            type: type,
            summary: type.summary,
            properties: rows(for: PropertyDiff.allKindKeys(type), prefix: NodePropertyCodec.kindPrefix)
        )
    }

    /// The key tables of the structured keys the document root carries beside its
    /// `children` — the `fonts` array, today. Themes, imports and variables have verbs of
    /// their own and are described there.
    public static var rootShapes: [PenNestedShape] {
        [PenFontDeclaration.schema]
    }

    /// Every nested key table any property of any type references, each named once.
    public static var nestedShapes: [PenNestedShape] {
        var seen = Set<String>()
        let tables = [common] + PenNode.NodeType.allCases.map { table(for: $0) }
        return tables.flatMap(\.nested).filter { seen.insert($0.name).inserted }
    }

    /// The node type a caller named, or `nil` if the format has no such type.
    ///
    /// - Parameter name: A type name as a .pen file writes it, such as `"text"`.
    /// - Returns: The type, or `nil`.
    public static func type(named name: String) -> PenNode.NodeType? {
        PenNode.NodeType(rawValue: name)
    }

    // MARK: - Private

    /// The codec fields the .pen file writes without a key of their own.
    ///
    /// A `ref`'s root overrides are the ref node's own top-level keys — `rootOverrides`
    /// is a name the codec has and the format does not. Printing it under `.pen key`
    /// invited a caller to write it, and ``PenNode/RefData``'s decoder sweeps a literal
    /// one straight back into the overrides as an override named `rootOverrides`.
    private static let inlinedFields: Set<String> = ["rootOverrides"]

    /// Turns a set of codec paths into sorted rows.
    ///
    /// - Parameters:
    ///   - paths: The codec paths to describe.
    ///   - prefix: The prefix they share, which the field name follows.
    /// - Returns: One row per path, sorted by path.
    private static func rows(for paths: Set<String>, prefix: String) -> [PenSchemaTable.Property] {
        paths.sorted().map { path in
            let field = String(path.dropFirst(prefix.count))
            return PenSchemaTable.Property(
                path: path,
                key: inlinedFields.contains(field) ? .inlined : .key(NodePropertyCodec.jsonKey(for: field)),
                shape: NodePropertyCodec.shape(of: field)
                    ?? PenPropertyShape(forms: [.open(PenValueForm.OpenShape(
                        phrase: "a valid \(field) value",
                        signature: "any"
                    ))])
            )
        }
    }
}
