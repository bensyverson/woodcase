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
/// Pen does both silently. This rule reports the first as a warning naming the node,
/// because it changes what a Woodcase render of the file shows. The second it does not
/// follow: a spread moves into the node's `metadata.woodcase.shadowSpread`
/// (``PenShadowSpread``), addressed to its effect's place and made for the migrated shadow,
/// so Woodcase still draws it and a later change to that shadow in Pen leaves it stale.
///
/// ```json
/// {"type": "shadow", "shadowType": "inner", "spread": 4, "blur": 8}
/// ```
/// becomes
/// ```json
/// {"type": "shadow", "shadowType": "outer", "blur": 8}
/// ```
/// with `{"effect": 0, "spread": 4, "shadow": {"type": "shadow", "shadowType": "outer", "blur": 8}}`
/// in the node's shadow spreads. A spread of 0 draws nothing and goes silently; one naming a
/// variable is discarded with a warning. One on an instance override is kept in the
/// override's own metadata, which expansion lays over the component node's key by key
/// (rule 6).
///
/// It runs for every document older than 2.19 — see ``PenLegacyMigrator/rules(upgrading:)``.
public struct PenShadowMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// Format 2.19, which changed shadows: a document declaring 2.19 or newer never gets
    /// this rule, so its inner shadows stay inner.
    public let target = PenFormatVersion(major: 2, minor: 19)

    /// Whether a document's bytes could hold anything this rule rewrites.
    ///
    /// A file with neither an `inner` nor a `spread` anywhere in it has no shadow to
    /// migrate. A `true` is only a maybe — `innerRadius` and `strokeAlignment: "inner"`
    /// match too.
    ///
    /// - Parameter data: The raw bytes of a .pen file.
    /// - Returns: `false` when the rule certainly changes nothing.
    public func mayApply(to data: Data) -> Bool {
        data.range(of: Data("inner".utf8)) != nil || data.range(of: Data("spread".utf8)) != nil
    }

    /// The key a node's effects live under, in the file's spelling.
    private static let effectKey = "effect"

    /// Rewrites the shadows among one node's effects, keeping their spreads in its metadata.
    ///
    /// `effect` may be one object or an array of them; anything else is left alone.
    public func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
        var spreads: [AnyCodable] = []
        switch node[Self.effectKey] {
        case let .dictionary(effect)?:
            node[Self.effectKey] = .dictionary(migrated(effect, at: 0, spreads: &spreads, id: id, diagnostics: diagnostics))
        case let .array(effects)?:
            node[Self.effectKey] = .array(effects.enumerated().map { index, value in
                guard case let .dictionary(effect) = value else { return value }
                return .dictionary(migrated(effect, at: index, spreads: &spreads, id: id, diagnostics: diagnostics))
            })
        default:
            break
        }
        guard !spreads.isEmpty else { return }
        PenMigrationMetadata.keep(.array(spreads), as: .shadowSpread, in: &node)
    }

    /// One effect object, migrated if it is a shadow, its spread appended to `spreads` as a
    /// stored ``PenShadowSpread`` entry.
    private func migrated(
        _ effect: [String: AnyCodable],
        at index: Int,
        spreads: inout [AnyCodable],
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
        switch result.removeValue(forKey: "spread") {
        case nil, .int(0)?, .double(0)?:
            break
        case let .int(number)?:
            spreads.append(entry(index, .int(number), shadow: result))
        case let .double(number)? where number.isFinite:
            spreads.append(entry(index, .double(number), shadow: result))
        case let other?:
            diagnostics?.warn(
                "Discarded shadow spread: \(PenPostIt.json(other)) is not a number of points",
                stage: .migration,
                nodeID: id
            )
        }
        return result
    }

    /// A stored ``PenShadowSpread`` entry.
    private func entry(_ index: Int, _ spread: AnyCodable, shadow: [String: AnyCodable]) -> AnyCodable {
        .dictionary(["effect": .int(index), "spread": spread, "shadow": .dictionary(shadow)])
    }
}
