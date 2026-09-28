//
//  PenIconMigrationRule.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// Rewrites a legacy `icon_font` node into the 2.17 `icon` shape.
///
/// `type: "icon_font"` becomes `"icon"`, `iconFontFamily` becomes `library`, and
/// `iconFontName` becomes `icon`. `weight` and `fill` carry over unchanged.
/// Nothing is discarded, so the rule emits no diagnostic.
public struct PenIconMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// Rewrites an `icon_font` node's type and keys in place.
    ///
    /// The two keys are renamed wherever they appear, not only on a node typed
    /// `icon_font`: a `ref` node's root overrides and its `descendants` property
    /// patches carry no `type`, and a 2.9 override of `iconFontName` that kept its
    /// old name would silently stop applying once the target node says `icon`.
    /// The key names are unique to icon nodes, so renaming them is always right.
    public func apply(toNode node: inout [String: AnyCodable], id _: String?, diagnostics _: PenDiagnosticCollector?) {
        if node["type"] == .string("icon_font") {
            node["type"] = .string("icon")
        }
        if let family = node.removeValue(forKey: "iconFontFamily") {
            node["library"] = family
        }
        if let name = node.removeValue(forKey: "iconFontName") {
            node["icon"] = name
        }
    }
}
