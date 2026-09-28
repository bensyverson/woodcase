//
//  PenShadowMigrationRule.swift
//  Woodcase
//

import Foundation

/// Brings a pre-2.19 document's shadows into format 2.19, the way Pen 1.2.14 does when
/// it opens one.
///
/// Two things changed in 2.19, and Pen rewrites both on open, in `children` and in `ref`
/// `descendants` override bags alike:
///
/// - **An inner shadow becomes an outer shadow.** `shadowType: "inner"` has been in the
///   format since 2.10, but every Pen before 1.2.14 drew it *outside* the shape. 1.2.14
///   is the first to draw it inside, so opening an older file converts it to `"outer"`,
///   which keeps the file looking the way it always looked in Pen.
/// - **`spread` is deleted.** 2.19 has no such key, and Pen refuses a new shadow that
///   carries one. No Pen ever drew it.
///
/// Pen does both silently. This rule reports each one as a warning naming the node,
/// because both change what a Woodcase render of the file shows.
///
/// ```json
/// {"type": "shadow", "shadowType": "inner", "spread": 4, "blur": 8}
/// ```
/// becomes
/// ```json
/// {"type": "shadow", "shadowType": "outer", "blur": 8}
/// ```
///
/// It runs for every document older than 2.19 — see ``PenLegacyMigrator/rules(upgrading:)``.
public struct PenShadowMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// Whether a document's bytes could hold anything this rule rewrites.
    ///
    /// A cheap byte search the parser runs before paying for a tree round trip: a file
    /// with neither an `inner` nor a `spread` anywhere in it has no shadow to migrate.
    /// A `true` is only a maybe — `innerRadius` and `strokeAlignment: "inner"` match too.
    ///
    /// - Parameter data: The raw bytes of a .pen file.
    /// - Returns: `false` when the rule certainly changes nothing.
    public static func mayApply(to data: Data) -> Bool {
        data.range(of: Data("inner".utf8)) != nil || data.range(of: Data("spread".utf8)) != nil
    }

    /// The key a node's effects live under, in the file's spelling.
    private static let effectKey = "effect"

    /// Rewrites the shadows among one node's effects.
    ///
    /// `effect` may be one object or an array of them; anything else is left alone.
    public func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
        switch node[Self.effectKey] {
        case let .dictionary(effect)?:
            node[Self.effectKey] = .dictionary(migrated(effect, id: id, diagnostics: diagnostics))
        case let .array(effects)?:
            node[Self.effectKey] = .array(effects.map { value in
                guard case let .dictionary(effect) = value else { return value }
                return .dictionary(migrated(effect, id: id, diagnostics: diagnostics))
            })
        default:
            break
        }
    }

    /// One effect object, migrated if it is a shadow.
    private func migrated(
        _ effect: [String: AnyCodable],
        id: String?,
        diagnostics: PenDiagnosticCollector?
    ) -> [String: AnyCodable] {
        guard effect["type"] == .string(PenEffect.EffectType.shadow.rawValue) else { return effect }
        var result = effect
        if result["shadowType"] == .string(PenEffect.PenShadowEffect.ShadowType.inner.rawValue) {
            result["shadowType"] = .string(PenEffect.PenShadowEffect.ShadowType.outer.rawValue)
            diagnostics?.warn(
                "Turned an inner shadow into an outer one: Pen drew it outside the shape before format 2.19, "
                    + "and migrates it the same way",
                stage: .migration,
                nodeID: id
            )
        }
        if result.removeValue(forKey: "spread") != nil {
            diagnostics?.warn(
                "Discarded shadow spread: format 2.19 has no equivalent, and no Pen ever drew it",
                stage: .migration,
                nodeID: id
            )
        }
        return result
    }
}
