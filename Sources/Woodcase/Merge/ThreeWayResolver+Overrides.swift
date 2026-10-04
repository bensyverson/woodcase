//
//  ThreeWayResolver+Overrides.swift
//  Woodcase
//

import Foundation

/// A `ref` node's overrides, merged per key rather than as two whole maps.
///
/// The change walk reports a ref's overrides as the coarse paths `kind.descendants`
/// and `kind.rootOverrides`; merged whole, an agent's new label text would collide
/// with a local color change on the same instance. So the descendant map merges per
/// descendant and key — a whole-node replacement (an entry with a `type`) as one
/// value — and the root overrides per key. The merged maps go back as one value each.
extension ThreeWayResolver {
    /// Merges one of a ref's override maps into `merged`.
    ///
    /// - Parameters:
    ///   - path: `kind.descendants` or `kind.rootOverrides`.
    ///   - id: The ref node's id.
    ///   - base: The node in the base, or `nil` when both sides added it.
    ///   - ours: The local node.
    ///   - theirs: The external node.
    ///   - merged: The merged node, whose map is replaced.
    ///   - kind: The conflict kind for a key both sides set differently.
    mutating func mergeOverrides(
        _ path: String, id: String, base: PenNode?, ours: PenNode, theirs: PenNode,
        into merged: inout PenNode, kind: MergeConflict.Kind
    ) {
        guard case var .ref(data) = merged.kind else { return }
        let baseData = base.flatMap(Self.refData)
        let oursData = Self.refData(ours)
        let theirsData = Self.refData(theirs)
        if path == "kind.rootOverrides" {
            let (result, clashes) = Self.mergeMap(baseData?.rootOverrides, oursData?.rootOverrides, theirsData?.rootOverrides)
            for clash in clashes {
                report(.rootOverride(nodeID: id, key: clash.key), kind, base: clash.base, ours: clash.ours, theirs: clash.theirs)
            }
            data.rootOverrides = result.isEmpty ? nil : result
        } else {
            let result = mergeDescendants(
                id: id, base: baseData?.descendants, ours: oursData?.descendants, theirs: theirsData?.descendants, kind: kind
            )
            data.descendants = result.isEmpty && (oursData?.descendants == nil || theirsData?.descendants == nil) ? nil : result
        }
        merged.kind = .ref(data)
    }

    /// Merges the descendant overrides per descendant and key.
    private mutating func mergeDescendants(
        id: String,
        base: [String: PenDescendantOverride]?,
        ours: [String: PenDescendantOverride]?,
        theirs: [String: PenDescendantOverride]?,
        kind: MergeConflict.Kind
    ) -> [String: PenDescendantOverride] {
        var result = ours ?? [:]
        let keys = Set((base ?? [:]).keys).union((theirs ?? [:]).keys)
        for descendant in keys.sorted() {
            let b = base?[descendant]
            let o = ours?[descendant]
            let t = theirs?[descendant]
            guard t != b else { continue }
            let replaced = [b, o, t].contains { $0?.isObjectReplacement == true }
            if replaced {
                if o == b {
                    result[descendant] = t
                } else if o != t {
                    report(
                        .descendantOverride(nodeID: id, descendant: descendant, key: nil), kind,
                        base: b.map { .dictionary($0.properties) }, ours: o.map { .dictionary($0.properties) },
                        theirs: t.map { .dictionary($0.properties) }
                    )
                }
                continue
            }
            let (properties, clashes) = Self.mergeMap(b?.properties, o?.properties, t?.properties)
            for clash in clashes {
                report(
                    .descendantOverride(nodeID: id, descendant: descendant, key: clash.key), kind,
                    base: clash.base, ours: clash.ours, theirs: clash.theirs
                )
            }
            result[descendant] = properties.isEmpty && t == nil ? nil : PenDescendantOverride(properties: properties)
        }
        return result
    }

    /// One key both sides of a map set differently.
    private struct Clash: Friendly {
        let key: String
        let base: AnyCodable?
        let ours: AnyCodable?
        let theirs: AnyCodable?
    }

    /// Merges a string-keyed map per key, starting from ours: a key theirs changed is
    /// taken when ours left it alone, and returned as a clash when both changed it
    /// differently. A missing key is `nil` throughout.
    private static func mergeMap(
        _ base: [String: AnyCodable]?,
        _ ours: [String: AnyCodable]?,
        _ theirs: [String: AnyCodable]?
    ) -> ([String: AnyCodable], [Clash]) {
        var result = ours ?? [:]
        var clashes: [Clash] = []
        let keys = Set((base ?? [:]).keys).union((theirs ?? [:]).keys)
        for key in keys.sorted() {
            let b = base?[key]
            let o = ours?[key]
            let t = theirs?[key]
            guard t != b else { continue }
            if o == b {
                result[key] = t
            } else if o != t {
                clashes.append(Clash(key: key, base: b, ours: o, theirs: t))
            }
        }
        return (result, clashes)
    }

    /// A node's ref payload, or `nil` for any other kind.
    private static func refData(_ node: PenNode) -> PenNode.RefData? {
        if case let .ref(data) = node.kind { return data }
        return nil
    }
}
