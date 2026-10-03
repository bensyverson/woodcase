//
//  PenMigrationRule.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// One rewrite applied to an older .pen JSON tree on its way to the current format's shape.
///
/// Rules operate on the raw JSON tree, not on decoded models: a legacy document
/// cannot be decoded by the current model at all, so the rewrite has to happen
/// before decoding. ``PenLegacyMigrator`` owns the traversal — a rule only says
/// what to do with the root object and with a single node's property dictionary,
/// and the migrator visits every node, nested child and `ref` descendant override.
///
/// Each rule names its ``target``: the format version whose shape it produces. A
/// document gets exactly the rules whose target is newer than the version it declares,
/// in target order — so a 2.19 file never re-runs the rule that made 2.19.
///
/// Both hooks default to doing nothing, so a rule implements only the one it needs.
///
/// ```swift
/// struct IconRenameRule: PenMigrationRule {
///     let target = PenFormatVersion.oldestModern
///
///     func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
///         guard node["type"] == .string("icon_font") else { return }
///         node["type"] = .string("icon")
///         node["library"] = node.removeValue(forKey: "iconFontFamily")
///         node["icon"] = node.removeValue(forKey: "iconFontName")
///     }
/// }
/// ```
///
/// Register a new rule by appending it to ``PenLegacyMigrator/rules``.
///
/// A rule that drops information the current model cannot express must say so
/// through the diagnostic collector, naming the node it came from.
public protocol PenMigrationRule: Sendable {
    /// The format version whose shape this rule produces.
    ///
    /// ``PenLegacyMigrator/rules(upgrading:)`` runs the rule for every document that
    /// declares an older version, and orders the rules it picks by this version. A rule
    /// that rewrites the legacy (2.8 – 2.10) shape targets ``PenFormatVersion/oldestModern``.
    var target: PenFormatVersion { get }

    /// Whether a document's bytes could hold anything this rule rewrites.
    ///
    /// A cheap byte search ``PenParser`` runs before paying for a tree round trip: when
    /// every rule a modern document needs answers `false`, the parser decodes the bytes
    /// as they are. A `true` is only a maybe.
    ///
    /// - Parameter data: The raw bytes of a .pen file.
    /// - Returns: `false` only when the rule certainly changes nothing.
    func mayApply(to data: Data) -> Bool

    /// Rewrites the document's root object — the place for `version` and other
    /// top-level keys. `children` is walked by the migrator, not here.
    ///
    /// - Parameters:
    ///   - document: The root JSON object, modified in place.
    ///   - diagnostics: Collector for information the rule discards.
    func apply(toDocument document: inout [String: AnyCodable], diagnostics: PenDiagnosticCollector?)

    /// Rewrites a single node's property dictionary.
    ///
    /// Called for every node in the document, including nodes nested in `children`
    /// and the property patches inside a `ref` node's `descendants` map.
    ///
    /// - Parameters:
    ///   - node: The node's JSON object, modified in place.
    ///   - id: The node's `id`, or — for a descendant override, which has none —
    ///     the slash-separated path that keys it.
    ///   - diagnostics: Collector for information the rule discards.
    func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?)
}

public extension PenMigrationRule {
    /// Always `true`: a rule without a byte hint is never skipped.
    func mayApply(to _: Data) -> Bool {
        true
    }

    /// Leaves the document root untouched.
    func apply(toDocument _: inout [String: AnyCodable], diagnostics _: PenDiagnosticCollector?) {}

    /// Leaves the node untouched.
    func apply(toNode _: inout [String: AnyCodable], id _: String?, diagnostics _: PenDiagnosticCollector?) {}
}
