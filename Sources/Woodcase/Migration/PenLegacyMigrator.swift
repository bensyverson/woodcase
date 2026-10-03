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
/// the rules ``rules(upgrading:)`` picks for its declared version: those whose
/// ``PenMigrationRule/target`` is newer than it. A legacy (2.8 – 2.10) document gets
/// every rule; a 2.17 one the 2.19 shadow rule and then the 2.20 image-mode rule; a 2.19
/// one only the image-mode rule. Call it directly only to migrate a file on disk.
///
/// ## Adding a rule
///
/// Each format change is one ``PenMigrationRule``. Write the rule in its own file next
/// to this one, give it the ``PenMigrationRule/target`` version it produces, and add it
/// to ``rules`` — that array is the whole registration point. Rules run in target order,
/// and in array order within one target, once per node, so a rule may rely on every
/// rule of an older target having already run.
public enum PenLegacyMigrator {
    /// Every rule, in the order they run: by ``PenMigrationRule/target``, then as listed.
    ///
    /// Add new rules here; this array is the migrator's whole registration point.
    public static let rules: [any PenMigrationRule] = inTargetOrder([
        PenIconMigrationRule(),
        PenRichTextMigrationRule(),
        PenStrokeMigrationRule(),
        PenGroupMigrationRule(),
        PenShadowMigrationRule(),
        PenImageModeMigrationRule(),
        PenVersionMigrationRule(),
    ])

    /// The rules a document declaring `version` needs to reach the model's shape.
    ///
    /// - Parameter version: The declared version, or `nil` for a document that declares
    ///   none, which is read as legacy.
    /// - Returns: The rules in ``rules`` whose target is newer than `version`, in the
    ///   order they run — every rule for a legacy document, and none for the model's
    ///   version or newer.
    public static func rules(upgrading version: PenFormatVersion?) -> [any PenMigrationRule] {
        guard let version else { return rules }
        return rules.filter { $0.target > version }
    }

    /// Sorts rules by target, keeping the listed order within one target.
    private static func inTargetOrder(_ rules: [any PenMigrationRule]) -> [any PenMigrationRule] {
        rules.enumerated()
            .sorted { ($0.element.target, $0.offset) < ($1.element.target, $1.offset) }
            .map(\.element)
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
