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
/// `dashPattern` and `miterAngle` left the format with no replacement in it, and move into
/// the node's `metadata.woodcase`, which Pen keeps and every Woodcase target draws:
///
/// - `dashPattern` becomes `strokeDash` (``PenStrokeDash``), unless the dash is one no
///   target draws (a negative length, all zeros) or sits on per-side widths.
/// - `miterAngle` — the sharpest corner, in degrees, still mitered — becomes
///   `strokeMiterLimit`, the miter limit that angle stands for: 1 / sin(angle / 2), kept to
///   four decimal places (``PenNode/strokeMiterLimit``). An angle naming a variable, or not
///   strictly between 0° and 180°, names no limit.
///
/// Either goes silently with its stroke when the stroke has no `fill`. Otherwise one that
/// cannot be kept is discarded with a diagnostic naming the node. One on an instance
/// override is kept in the override's own metadata, which expansion lays over the component
/// node's key by key (rule 6).
public struct PenStrokeMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// The 2.11 shape: only a legacy (2.8 – 2.10) document gets this rule.
    public let target = PenFormatVersion.oldestModern

    /// Rewrites one node's nested `stroke` object into the flat 2.17 keys.
    ///
    /// A node whose `stroke` is not an object is left alone: the rule only ever runs on
    /// 2.8 – 2.10 documents, where the nested object is the only shape `stroke` takes.
    public func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
        guard case let .dictionary(stroke)? = node["stroke"] else { return }

        guard let paint = stroke["fill"] else {
            node["stroke"] = nil
            return
        }
        if let dash = stroke["dashPattern"] {
            keep(dash, perSide: isPerSide(stroke["thickness"]), in: &node, id: id, diagnostics: diagnostics)
        }
        if let angle = stroke["miterAngle"] {
            keep(miterAngle: angle, in: &node, id: id, diagnostics: diagnostics)
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

    // MARK: - Dash

    /// Moves a legacy dash into `metadata.woodcase.strokeDash`, beside whatever metadata the
    /// node already has, or reports it discarded when no target could draw it.
    private func keep(
        _ dash: AnyCodable,
        perSide: Bool,
        in node: inout [String: AnyCodable],
        id: String?,
        diagnostics: PenDiagnosticCollector?
    ) {
        if let problem = PenStrokeDash.problem(in: dash) {
            diagnostics?.warn("Discarded stroke dashPattern: it \(problem.reason)", stage: .migration, nodeID: id)
            return
        }
        if perSide {
            diagnostics?.warn(
                "Discarded stroke dashPattern: a dash cannot flow round per-side stroke widths",
                stage: .migration, nodeID: id
            )
            return
        }
        guard PenStrokeDash.lengths(in: dash)?.isEmpty == false else { return }
        PenMigrationMetadata.keep(dash, as: .strokeDash, in: &node)
    }

    // MARK: - Miter

    /// Moves a legacy miter angle into `metadata.woodcase.strokeMiterLimit` as the limit it
    /// stands for, or reports it discarded when it names none or has nowhere to go.
    private func keep(
        miterAngle angle: AnyCodable,
        in node: inout [String: AnyCodable],
        id: String?,
        diagnostics: PenDiagnosticCollector?
    ) {
        guard let limit = Self.miterLimit(forAngle: angle) else {
            diagnostics?.warn(
                "Discarded stroke miterAngle: \(PenPostIt.json(angle)) is not an angle strictly between 0 and 180 degrees",
                stage: .migration, nodeID: id
            )
            return
        }
        PenMigrationMetadata.keep(PenMigrationMetadata.number(limit), as: .strokeMiterLimit, in: &node)
    }

    /// The miter limit a miter angle stands for — 1 / sin(angle / 2), to four decimal
    /// places — or `nil` for an angle that is not a number strictly between 0° and 180°.
    ///
    /// A miter's length, in stroke widths, is 1 / sin(θ / 2) at a corner of angle θ, so the
    /// sharpest corner still mitered names the limit.
    static func miterLimit(forAngle angle: AnyCodable) -> Double? {
        let degrees: Double? = switch angle {
        case let .int(number): Double(number)
        case let .double(number): number
        default: nil
        }
        guard let degrees, degrees > 0, degrees < 180 else { return nil }
        return (10000 / sin(degrees * .pi / 360)).rounded() / 10000
    }

    /// Whether a legacy `thickness` writes a width per side.
    private func isPerSide(_ thickness: AnyCodable?) -> Bool {
        if case .dictionary? = thickness { return true }
        return false
    }
}
