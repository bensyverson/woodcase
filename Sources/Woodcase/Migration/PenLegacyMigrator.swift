//
//  PenLegacyMigrator.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// Rewrites an older .pen JSON tree into the current format's shape.
///
/// Woodcase keeps **one** in-memory model, the current one. An older file is
/// brought up to it before decoding, at the JSON level: the migrator walks the
/// raw tree and applies every rule in ``rules`` to the document root and to each
/// node — top-level nodes, everything nested under `children`, and the property
/// patches inside a `ref` node's `descendants` map.
///
/// ```swift
/// let tree = try JSONDecoder().decode([String: AnyCodable].self, from: data)
/// let migrated = PenLegacyMigrator.migrate(tree, diagnostics: diagnostics)
/// ```
///
/// ``PenParser`` runs this automatically for any document older than the model, with
/// the rules ``rules(upgrading:)`` picks for its declared version: everything in
/// ``rules`` for a legacy (2.8 – 2.10) document, only ``modernRules`` for a 2.11 – 2.18
/// one. Call it directly only to migrate a file on disk.
///
/// ## Adding a rule
///
/// Each format change is one ``PenMigrationRule``. Write the rule in its own file next
/// to this one and add it to ``rules`` — and, for a change after 2.17, to
/// ``modernRules`` as well; those two arrays are the whole registration point. Rules
/// run in array order, once per node, so a rule may rely on rules listed before it
/// having already run.
public enum PenLegacyMigrator {
    /// The rules applied to every legacy document, in order.
    ///
    /// Append new rules here; this array is the migrator's whole registration point.
    public static let rules: [any PenMigrationRule] = [
        PenIconMigrationRule(),
        PenRichTextMigrationRule(),
        PenVersionMigrationRule(),
        PenStrokeMigrationRule(),
        PenGroupMigrationRule(),
        PenShadowMigrationRule(),
    ]

    /// The rules applied to a document between 2.11 and the model's version: the format
    /// changes made after 2.17, which a 2.11 – 2.18 file has not seen.
    public static let modernRules: [any PenMigrationRule] = [
        PenVersionMigrationRule(),
        PenShadowMigrationRule(),
    ]

    /// The rules a document declaring `version` needs to reach the model's shape.
    ///
    /// - Parameter version: The declared version, or `nil` for a document that declares
    ///   none, which is read as legacy.
    /// - Returns: ``rules`` for a legacy document, ``modernRules`` for one of 2.11 up to
    ///   the model, and nothing for the model's version or newer.
    public static func rules(upgrading version: PenFormatVersion?) -> [any PenMigrationRule] {
        guard let version, version > PenFormatVersion.newestLegacy else { return rules }
        return version < PenFormatVersion.current ? modernRules : []
    }

    /// Rewrites an older document tree into the current format's shape.
    ///
    /// - Parameters:
    ///   - document: The raw JSON object decoded from the .pen file.
    ///   - rules: The rules to apply. Defaults to ``rules``; pass a subset to test one rule.
    ///   - diagnostics: Collector notified of every property the migration discards.
    /// - Returns: A tree the current ``PenDocument`` model can decode.
    public static func migrate(
        _ document: [String: AnyCodable],
        rules: [any PenMigrationRule] = PenLegacyMigrator.rules,
        diagnostics: PenDiagnosticCollector? = nil
    ) -> [String: AnyCodable] {
        var result = document
        for rule in rules {
            rule.apply(toDocument: &result, diagnostics: diagnostics)
        }
        if case let .array(children)? = result["children"] {
            result["children"] = .array(children.map {
                migrate(nodeValue: $0, fallbackID: nil, rules: rules, diagnostics: diagnostics)
            })
        }
        return result
    }

    // MARK: - Traversal

    /// Applies the node rules to one node and recurses into its children and descendant overrides.
    ///
    /// Values that are not JSON objects are passed through untouched, so a malformed
    /// tree degrades rather than crashing.
    private static func migrate(
        nodeValue: AnyCodable,
        fallbackID: String?,
        rules: [any PenMigrationRule],
        diagnostics: PenDiagnosticCollector?
    ) -> AnyCodable {
        guard case var .dictionary(node) = nodeValue else { return nodeValue }

        let id: String? = if case let .string(value)? = node["id"] { value } else { fallbackID }
        for rule in rules {
            rule.apply(toNode: &node, id: id, diagnostics: diagnostics)
        }

        if case let .array(children)? = node["children"] {
            node["children"] = .array(children.map {
                migrate(nodeValue: $0, fallbackID: nil, rules: rules, diagnostics: diagnostics)
            })
        }

        if case let .dictionary(descendants)? = node["descendants"] {
            var migrated: [String: AnyCodable] = [:]
            for (path, override) in descendants {
                migrated[path] = migrate(
                    nodeValue: override, fallbackID: path, rules: rules, diagnostics: diagnostics
                )
            }
            node["descendants"] = .dictionary(migrated)
        }

        return .dictionary(node)
    }
}
