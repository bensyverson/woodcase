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
/// Both hooks default to doing nothing, so a rule implements only the one it needs.
///
/// ```swift
/// struct IconRenameRule: PenMigrationRule {
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
    /// Leaves the document root untouched.
    func apply(toDocument _: inout [String: AnyCodable], diagnostics _: PenDiagnosticCollector?) {}

    /// Leaves the node untouched.
    func apply(toNode _: inout [String: AnyCodable], id _: String?, diagnostics _: PenDiagnosticCollector?) {}
}
