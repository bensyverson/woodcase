//
//  PenStrokeMigrationRule.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// Flattens a legacy nested `stroke` object into .pen 2.17's sibling stroke keys.
///
/// Up to 2.10 a stroke was one object on the node:
///
/// ```json
/// "stroke": { "align": "inside", "thickness": 2, "join": "miter", "cap": "round", "fill": "#000000" }
/// ```
///
/// 2.17 spells the same stroke as five keys beside `fill`:
///
/// ```json
/// "stroke": "#000000", "strokeWidth": 2, "strokeAlignment": "inner", "strokeLinecap": "round"
/// ```
///
/// The mapping is `fill` → `stroke`, `thickness` → `strokeWidth`, `join` → `strokeLinejoin`,
/// `cap` → `strokeLinecap`, `align` → `strokeAlignment` with `inside`/`outside` renamed to
/// `inner`/`outer`. The legacy cap `none` becomes `butt`.
///
/// Two behaviors copy version 1.2.7 of the format's own editor exactly, because its own
/// re-saves of our fixtures are the oracle for this migration:
///
/// - **Defaults are omitted.** A centered alignment, a mitered join and a butt cap are written
///   as nothing at all, so a migrated tree compares equal to that editor's own save.
/// - **A stroke with no `fill` is dropped entirely** — width, join and all. Such a stroke has
///   no paint and draws nothing, and that editor discards it rather than carrying a widow width.
///
/// `dashPattern` and `miterAngle` left the format with no replacement; each is discarded with
/// a diagnostic naming the node it came from.
public struct PenStrokeMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// Rewrites one node's nested `stroke` object into the flat 2.17 keys.
    ///
    /// A node whose `stroke` is not an object is left alone: the rule only ever runs on
    /// 2.8 – 2.10 documents, where the nested object is the only shape `stroke` takes.
    public func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
        guard case let .dictionary(stroke)? = node["stroke"] else { return }

        report(discarded: "dashPattern", from: stroke, id: id, to: diagnostics)
        report(discarded: "miterAngle", from: stroke, id: id, to: diagnostics)

        guard let paint = stroke["fill"] else {
            node["stroke"] = nil
            return
        }

        node["stroke"] = paint
        node["strokeWidth"] = stroke["thickness"]
        node["strokeLinejoin"] = nonDefault(stroke["join"], default: PenStrokeJoin.miter.rawValue)
        node["strokeLinecap"] = nonDefault(linecap(stroke["cap"]), default: PenStrokeCap.butt.rawValue)
        node["strokeAlignment"] = nonDefault(alignment(stroke["align"]), default: PenStrokeAlign.center.rawValue)
    }

    // MARK: - Value mapping

    /// Renames the legacy `inside`/`outside` alignment to 2.17's `inner`/`outer`.
    private func alignment(_ value: AnyCodable?) -> AnyCodable? {
        guard case let .string(raw)? = value else { return value }
        switch raw {
        case "inside": return .string(PenStrokeAlign.inner.rawValue)
        case "outside": return .string(PenStrokeAlign.outer.rawValue)
        default: return value
        }
    }

    /// Maps the retired `none` cap onto `butt`, which draws the same way.
    private func linecap(_ value: AnyCodable?) -> AnyCodable? {
        guard case .string("none")? = value else { return value }
        return .string(PenStrokeCap.butt.rawValue)
    }

    /// Drops a value that equals the .pen default, the way the format's own editor does on save.
    private func nonDefault(_ value: AnyCodable?, default defaultValue: String) -> AnyCodable? {
        value == .string(defaultValue) ? nil : value
    }

    // MARK: - Diagnostics

    /// Reports a stroke property that 2.17 cannot express, if the legacy stroke carried one.
    private func report(
        discarded key: String,
        from stroke: [String: AnyCodable],
        id: String?,
        to diagnostics: PenDiagnosticCollector?
    ) {
        guard stroke[key] != nil else { return }
        diagnostics?.warn(
            "Discarded stroke \(key): the .pen 2.17 format has no equivalent",
            stage: .migration,
            nodeID: id
        )
    }
}
