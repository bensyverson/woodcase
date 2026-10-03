//
//  PenVersionMigrationRule.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// Stamps the current format version on a migrated document.
///
/// Whatever the file declared — 2.8, 2.9, 2.10, 2.17, or nothing at all — the rewritten
/// tree is a tree of the model's version and says so.
/// Nothing is discarded, so the rule emits no diagnostic.
public struct PenVersionMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// The model's version: every older document is stamped.
    public let target = PenFormatVersion.current

    /// Always `false`: ``PenParser`` stamps the model's version on every document it
    /// migrates, tree or no tree, so the version alone never needs the tree.
    public func mayApply(to _: Data) -> Bool {
        false
    }

    /// Sets the root `version` key to ``PenDocument/currentFormatVersion``.
    public func apply(toDocument document: inout [String: AnyCodable], diagnostics _: PenDiagnosticCollector?) {
        document["version"] = .string(PenDocument.currentFormatVersion)
    }
}
