//
//  DocumentLinter+ShadowSpread.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/shadowSpreadStale`` check.
///
/// A node's `metadata.woodcase.shadowSpread` entries each hold the shadow they were made
/// for (``PenShadowSpread``). When the effect at an entry's place is no longer that shadow —
/// Pen, which keeps metadata but cannot see it, changed, moved or removed the effect; or a
/// write changed `effect` without restating the spreads — the entry is ignored and the
/// shadow casts without spread rather than spreading the wrong one. The finding names the
/// effect and both ways out.
extension DocumentLinter {
    /// A finding when any of a node's shadow spreads is stale.
    ///
    /// A row inside an instance is skipped: its spreads are the component's, reported once on
    /// the component's own node.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders.
    /// - Returns: At most one finding.
    static func shadowSpreadStale(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard !row.id.contains(NodeAddress.separator) else { return [] }
        let effects = PenRenderer.effects(for: node)
        let stale = node.shadowSpreads.filter { $0.isStale(for: effects) }.map(\.effect)
        guard !stale.isEmpty else { return [] }
        let key = PenMetadata.WoodcaseKey.shadowSpread.path
        let places = stale.map { "effect \($0)" }.joined(separator: ", ")
        return [finding(
            .shadowSpreadStale, row,
            "has a shadow spread for \(places) made for a shadow it no longer has there, so it casts without "
                + "it. Restate `\(key)` for the shadow as it is now, or remove it with "
                + "`woodcase set <file> \(row.id) \(key)=null`."
        )]
    }
}
